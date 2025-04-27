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

// Output reservoirs
RWTexture2D<float4> g_ReservoirY_Out : register(u0); // xyz: stored sample position, w: hasValue flag
RWTexture2D<float4> g_ReservoirWeight_Out : register(u1); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
RWTexture2D<float4> g_LightSample_Out : register(u2); // xyz: light color/intensity, w: not used
RWTexture2D<float4> g_LightNormalArea_Out : register(u3); // xyz: light normal, w: light area

ConstantBuffer<TextureDimConstantBuffer> cb : register(b0);
ConstantBuffer<PathtracerConstantBuffer> g_cb : register(b1);


float EvalP(float3 toLight, float3 diffuse, float3 radiance, float3 normal)
{
    float NdotL = max(0.0, dot(toLight, normal));
    float3 brdf = diffuse * (1.0f / PI); // Lambertian
    float3 color = brdf * radiance * NdotL;
    return length(color); // scalar pdf target
}

void UpdateReservoir(inout float4 y, inout float4 lightSample, inout float4 lightNormalArea,
                     inout float wSum, inout int M,
                     float4 candidateY, float4 candidateLightSample, float4 candidateLightNormalArea,
                     float w, inout uint seed)
{
    wSum = wSum + w;
    M = M + 1;
    if (wSum > 0 && RNG::Random01(seed) < (w / wSum))
    {
        y = candidateY;
        lightSample = candidateLightSample;
        lightNormalArea = candidateLightNormalArea;
    }
}

uint2 GetPrevFramePixelPos(float4 worldPos, float width, float height, inout bool inScreen)
{
    float4 prevClipPos = mul(float4(worldPos.xyz, 1.0), g_cb.prevFrameViewProj);
    float2 prevNDC = prevClipPos.xy / prevClipPos.w;
    float2 prevUV = prevNDC * float2(0.5, -0.5) + 0.5;
    int2 prevPixelPos = int2(prevUV * float2(width, height));
    
    inScreen = (prevPixelPos.x >= 0 && prevPixelPos.x < width &&
                prevPixelPos.y >= 0 && prevPixelPos.y < height);
    
    return uint2(prevPixelPos);
}

bool IsValidPosition(float4 pos)
{
    return pos.w != 0.0f;
}

[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    uint2 pixelPos = DTid.xy;
    float width = cb.textureDim.x;
    float height = cb.textureDim.y;
    
    // Check if pixel is within bounds
    if (pixelPos.x >= width || pixelPos.y >= height)
        return;
    
    // Load current data
    float4 worldPos = g_rtGBufferPosition[pixelPos];
    
    // Skip invalid positions
    if (!IsValidPosition(worldPos) || g_cb.frameIndex == 0)
    {
        g_ReservoirY_Out[pixelPos] = g_ReservoirY_In[pixelPos];
        g_ReservoirWeight_Out[pixelPos] = g_ReservoirWeight_In[pixelPos];
        g_LightSample_Out[pixelPos] = g_LightSample_In[pixelPos];
        g_LightNormalArea_Out[pixelPos] = g_LightNormalArea_In[pixelPos];
        return;
    }
    
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[pixelPos];
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    float3 diffuse = g_rtAOSurfaceAlbedo[pixelPos].rgb;
    
    // Initialize random seed based on pixel position and frame index
    uint seed = RNG::SeedThread(pixelPos.x * 19349663 ^ pixelPos.y * 83492791 ^ g_cb.frameIndex * 73856093);
    // Load current frame reservoir data
    float4 currentY = g_ReservoirY_In[pixelPos];
    float4 currentWeight = g_ReservoirWeight_In[pixelPos]; // x: W_Y, y: w_sum, z: M, w: frame counter
    float4 currentLightSample = g_LightSample_In[pixelPos];
    float4 currentLightNormalArea = g_LightNormalArea_In[pixelPos];
    
    float currentW = currentWeight.x;
    float currentWsum = currentWeight.y;
    int currentM = (int) currentWeight.z;
    
    // Find corresponding pixel in previous frame
    bool inScreen;
    uint2 prevPixelPos = GetPrevFramePixelPos(worldPos, width, height, inScreen);
    
    // If previous frame pixel is valid, combine the reservoirs
    if (inScreen)
    {
        float4 prevWorldPos = g_rtGBufferPosition[prevPixelPos];
        
        // Only combine if the previous pixel is valid and not too far from current position
        if (IsValidPosition(prevWorldPos) && distance(prevWorldPos.xyz, worldPos.xyz) < 0.01f)
        {
            // Load previous frame reservoir data
            float4 prevY = g_PrevReservoirY_In[prevPixelPos];
            float4 prevWeight = g_PrevReservoirWeight_In[prevPixelPos];
            float4 prevLightSample = g_PrevLightSample_In[prevPixelPos];
            float4 prevLightNormalArea = g_PrevLightNormalArea_In[prevPixelPos];
            
            float prevW = prevWeight.x;
            float prevWsum = prevWeight.y;
            int prevM = (int) prevWeight.z;
            
            // Limit number of samples in previous reservoir (prevent too much bias)
            if (prevM > 20 * currentM)
            {
                prevWsum *= (20.0f * currentM) / prevM;
                prevM = 20 * currentM;
            }
            
            // Create output reservoir - start with empty values
            float4 outY = float4(0, 0, 0, 0);
            float4 outLightSample = float4(0, 0, 0, 0);
            float4 outLightNormalArea = float4(0, 0, 0, 0);
            float outWsum = 0.0f;
            float outW = 0.0f;
            int outM = 0;
            
            // Only consider valid samples
            if (currentY.w > 0.5f)
            {
                float3 toLight = normalize(currentY.xyz - worldPos.xyz);
                float w1 = EvalP(toLight, diffuse, currentLightSample.xyz, worldNormal) *
                          currentW * float(currentM);
                UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, outM,
                               currentY, currentLightSample, currentLightNormalArea, w1, seed);
            }
            
            if (prevY.w > 0.5f)
            {
                float3 toLight = normalize(prevY.xyz - worldPos.xyz);
                float w2 = EvalP(toLight, diffuse, prevLightSample.xyz, worldNormal) *
                          prevW * float(prevM);
                UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, outM,
                               prevY, prevLightSample, prevLightNormalArea, w2, seed);
            }
            
            // Update combined reservoir stats
            outM = currentM + prevM;
            
            // Calculate new weight
            if (outY.w > 0.5f)
            {
                float3 toLight = normalize(outY.xyz - worldPos.xyz);
                float p_hat = EvalP(toLight, diffuse, outLightSample.xyz, worldNormal);
                
                if (p_hat > 0.0f)
                {
                    outW = (outWsum / outM) / p_hat;
                }
                else
                {
                    outW = 0.0f;
                }
            }
            
            // Output the combined reservoir
            g_ReservoirY_Out[pixelPos] = outY;
            g_ReservoirWeight_Out[pixelPos] = float4(outW, outWsum, outM, currentWeight.w + 1);
            g_LightSample_Out[pixelPos] = outLightSample;
            g_LightNormalArea_Out[pixelPos] = outLightNormalArea;
            
            return;
        }
    }
    
    // If we couldn't use previous frame data, just copy current frame data
    g_ReservoirY_Out[pixelPos] = g_ReservoirY_In[pixelPos];
    g_ReservoirWeight_Out[pixelPos] = g_ReservoirWeight_In[pixelPos];
    g_LightSample_Out[pixelPos] = g_LightSample_In[pixelPos];
    g_LightNormalArea_Out[pixelPos] = g_LightNormalArea_In[pixelPos];
}