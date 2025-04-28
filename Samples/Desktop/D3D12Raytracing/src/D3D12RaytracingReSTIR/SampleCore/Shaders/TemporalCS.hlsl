#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"
#include "RandomNumberGenerator.hlsli"

// Input G-Buffer textures
Texture2D<float4> g_rtGBufferPosition : register(t0); // World space position (xyz) + flag (w)
Texture2D<NormalDepthTexFormat> g_rtGBufferNormalDepth : register(t1); // Normal (xyz) + depth (w)
Texture2D<float4> g_rtAOSurfaceAlbedo : register(t2); // Surface albedo/material diffuse


// Input previous state reservoirs
Texture2D<float4> g_PrevReservoirY_In : register(t3); // xyz: stored sample position, w: hasValue flag (1.0 if valid)
Texture2D<float4> g_PrevReservoirWeight_In : register(t4); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
Texture2D<float4> g_PrevLightSample_In : register(t5); // xyz: light color/intensity, w: not used
Texture2D<float4> g_PrevLightNormalArea_In : register(t6); // xyz: light normal, w: light area

// Input current state reservoirs
Texture2D<float4> g_ReservoirY_In : register(t7); // xyz: stored sample position, w: hasValue flag (1.0 if valid)
Texture2D<float4> g_ReservoirWeight_In : register(t8); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
Texture2D<float4> g_LightSample_In : register(t9); // xyz: light color/intensity, w: not used
Texture2D<float4> g_LightNormalArea_In : register(t10); // xyz: light normal, w: light area
Texture2D<float2> g_rtTextureSpaceMotionVector : register(t11); // Texture space motion vector (x: dx, y: dy)

// Output reservoirs
RWTexture2D<float4> g_ReservoirY_Out : register(u0); // xyz: stored sample position, w: hasValue flag
RWTexture2D<float4> g_ReservoirWeight_Out : register(u1); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
RWTexture2D<float4> g_LightSample_Out : register(u2); // xyz: light color/intensity, w: not used
RWTexture2D<float4> g_LightNormalArea_Out : register(u3); // xyz: light normal, w: light area

ConstantBuffer<TextureDimConstantBuffer> cb : register(b0);
ConstantBuffer<PathtracerConstantBuffer> g_cb : register(b1);

// Optimized version of EvalP function
float EvalP(float3 toLight, float3 diffuse, float3 radiance, float3 normal)
{
    float NdotL = max(0.0, dot(toLight, normal));
    // Combined diffuse BRDF calculation with radiance and NdotL in one step
    float3 color = diffuse * radiance * NdotL * (1.0f / PI);
    return length(color); // scalar pdf target
}

// Optimized reservoir update function using inout parameters
void UpdateReservoir(inout float4 y, inout float4 lightSample, inout float4 lightNormalArea,
                     inout float wSum, inout int M,
                     float4 candidateY, float4 candidateLightSample, float4 candidateLightNormalArea,
                     float w, inout uint seed)
{
    wSum += w;
    M += 1;
    if (wSum > 0 && RNG::Random01(seed) < (w / wSum))
    {
        y = candidateY;
        lightSample = candidateLightSample;
        lightNormalArea = candidateLightNormalArea;
    }
}

// Simple inline function for position validity check
bool IsValidPosition(float4 pos)
{
    return pos.w != 0.0f;
}

[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    if ((g_cb.restirMode & 0x02) == 0) {
        g_ReservoirY_Out[DTid] = g_ReservoirY_In[DTid];
        g_ReservoirWeight_Out[DTid] = g_ReservoirWeight_In[DTid];
        g_LightSample_Out[DTid] = g_LightSample_In[DTid];
        g_LightNormalArea_Out[DTid] = g_LightNormalArea_In[DTid];
        return; // Skip if not in temporal mode
    }
    // Cache texture dimensions as locals
    const float width = cb.textureDim.x;
    const float height = cb.textureDim.y;
    
    // Early boundary check
    if (DTid.x >= width || DTid.y >= height)
        return;
    
    // Load current pixel data
    float4 worldPos = g_rtGBufferPosition[DTid];
    
    // Skip invalid positions and first frame - fast path with minimal texture operations
    if (!IsValidPosition(worldPos) || g_cb.frameIndex == 0)
    {
        // Direct copy from input to output using the same indices
        g_ReservoirY_Out[DTid] = g_ReservoirY_In[DTid];
        g_ReservoirWeight_Out[DTid] = g_ReservoirWeight_In[DTid];
        g_LightSample_Out[DTid] = g_LightSample_In[DTid];
        g_LightNormalArea_Out[DTid] = g_LightNormalArea_In[DTid];
        return;
    }
    
    // Load current frame G-buffer data - only fetch what we need
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[DTid];
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    float3 diffuse = g_rtAOSurfaceAlbedo[DTid].rgb;
    
    // Initialize random seed based on pixel position and frame index
    uint seed = RNG::SeedThread(DTid.x * 19349663 ^ DTid.y * 83492791 ^ g_cb.frameIndex * 73856093);
    
    // Load current frame reservoir data at once to reduce texture fetches
    float4 currentY = g_ReservoirY_In[DTid];
    float4 currentWeight = g_ReservoirWeight_In[DTid]; // x: W_Y, y: w_sum, z: M, w: frame counter
    float4 currentLightSample = g_LightSample_In[DTid];
    float4 currentLightNormalArea = g_LightNormalArea_In[DTid];
    
    // Cache world position for repeated use
    float3 worldPosXYZ = worldPos.xyz;
    
    // Find corresponding pixel in previous frame
    float2 dxdy = g_rtTextureSpaceMotionVector[DTid];
    uint2 dxdyScreen = uint2(dxdy.x * width, dxdy.y * height);
    uint2 prevPixelPos = DTid + dxdyScreen;
    // If previous frame pixel is valid, combine the reservoirs
    if (prevPixelPos.x < width && prevPixelPos.y < height && prevPixelPos.x >= 0 && prevPixelPos.y >= 0)
    {
        // float4 prevWorldPos = g_rtGBufferPosition[prevPixelPos];
        
        // Check if previous pixel is valid and close enough to current position
        // float3 posDiff = prevWorldPos.xyz - worldPosXYZ;
        // float distSquared = dot(posDiff, posDiff);
        
        if (true)
        {
            // Load previous frame reservoir data in one batch
            float4 prevY = g_PrevReservoirY_In[prevPixelPos];
            float4 prevWeight = g_PrevReservoirWeight_In[prevPixelPos];
            float4 prevLightSample = g_PrevLightSample_In[prevPixelPos];
            float4 prevLightNormalArea = g_PrevLightNormalArea_In[prevPixelPos];
            
            // Extract reservoir stats
            float currentW = currentWeight.x;
            float currentWsum = currentWeight.y;
            int currentM = (int) currentWeight.z;
            
            float prevW = prevWeight.x;
            float prevWsum = prevWeight.y;
            int prevM = (int) prevWeight.z;
            
            // Limit number of samples in previous reservoir (prevent too much bias)
            // Use multiplication instead of division when possible
            const float MAX_RATIO = 20.0f;
            if (prevM > MAX_RATIO * currentM)
            {
                float scaleFactor = MAX_RATIO * currentM / prevM;
                prevWsum *= scaleFactor;
                prevM = MAX_RATIO * currentM;
            }
            
            // Create output reservoir with local variables
            float4 outY = float4(0, 0, 0, 0);
            float4 outLightSample = float4(0, 0, 0, 0);
            float4 outLightNormalArea = float4(0, 0, 0, 0);
            float outWsum = 0.0f;
            float outW = 0.0f;
            int outM = 0;
            
            // Only process valid samples (currentY.w > 0.5f)
            if (currentY.w > 0.5f)
            {
                float3 toLight = normalize(currentY.xyz - worldPosXYZ);
                float pdfValue = EvalP(toLight, diffuse, currentLightSample.xyz, worldNormal);
                float w1 = pdfValue * currentW * float(currentM);
                
                UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, outM,
                               currentY, currentLightSample, currentLightNormalArea, w1, seed);
            }
            
            // Only process valid samples (prevY.w > 0.5f)
            if (prevY.w > 0.5f)
            {
                float3 toLight = normalize(prevY.xyz - worldPosXYZ);
                float pdfValue = EvalP(toLight, diffuse, prevLightSample.xyz, worldNormal);
                float w2 = pdfValue * prevW * float(prevM);
                
                UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, outM,
                               prevY, prevLightSample, prevLightNormalArea, w2, seed);
            }
            
            // Update combined reservoir stats
            outM = currentM + prevM;
            
            // Calculate new weight
            if (outY.w > 0.5f)
            {
                float3 toLight = normalize(outY.xyz - worldPosXYZ);
                float p_hat = EvalP(toLight, diffuse, outLightSample.xyz, worldNormal);
                
                // Avoid division by zero using conditional operator
                outW = (p_hat > 0.0f) ? ((outWsum / outM) / p_hat) : 0.0f;
            }
            
            // Output the combined reservoir in one batch
            g_ReservoirY_Out[DTid] = outY;
            g_ReservoirWeight_Out[DTid] = float4(outW, outWsum, outM, currentWeight.w + 1);
            g_LightSample_Out[DTid] = outLightSample;
            g_LightNormalArea_Out[DTid] = outLightNormalArea;
            
            return;
        }
    }
    
    // If we couldn't use previous frame data, just copy current frame data
    // Use the same index (DTid) for both input and output to improve cache coherence
    g_ReservoirY_Out[DTid] = currentY;
    g_ReservoirWeight_Out[DTid] = currentWeight;
    g_LightSample_Out[DTid] = currentLightSample;
    g_LightNormalArea_Out[DTid] = currentLightNormalArea;
}