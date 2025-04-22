#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"

// Input G-Buffer textures
Texture2D<float4> g_rtGBufferPosition : register(t0); // World space position (xyz) + flag (w)
Texture2D<NormalDepthTexFormat> g_rtGBufferNormalDepth : register(t1); // Normal (xyz) + depth (w)
Texture2D<float4> g_rtAOSurfaceAlbedo : register(t2); // Surface albedo/material diffuse

// Input current state reservoirs
Texture2D<float4> g_ReservoirY_In : register(t3); // xyz: stored sample position, w: hasValue flag (1.0 if valid)
Texture2D<float4> g_ReservoirWeight_In : register(t4); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
Texture2D<float4> g_LightSample_In : register(t5); // xyz: light color/intensity, w: not used
Texture2D<float4> g_LightNormalArea_In : register(t6); // xyz: light normal, w: light area

// Output reservoirs
RWTexture2D<float4> g_ReservoirY_Out : register(u0); // xyz: stored sample position, w: hasValue flag
RWTexture2D<float4> g_ReservoirWeight_Out : register(u1); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
RWTexture2D<float4> g_LightSample_Out : register(u2); // xyz: light color/intensity, w: not used
RWTexture2D<float4> g_LightNormalArea_Out : register(u3); // xyz: light normal, w: light area

// Constant buffer
ConstantBuffer<TextureDimConstantBuffer> cb : register(b0);

float EvalP(float3 toLight, float3 diffuse, float3 radiance, float3 normal)
{
    float NdotL = max(0.0, dot(toLight, normal));
    float3 brdf = diffuse * (1.0f / PI); // Lambertian
    float3 color = brdf * radiance * NdotL;
    return length(color); // scalar pdf target
}

// Permuted Congruential Generator (PCG)-style hash
uint initRand(uint seed, uint frameCount, uint sampleIndex)
{
    uint state = seed;
    state ^= frameCount * 747796405u;
    state ^= sampleIndex * 2891336453u;
    state ^= (state >> 16);
    state *= 2246822519u;
    state ^= (state >> 13);
    state *= 3266489917u;
    state ^= (state >> 16);
    return state;
}

float nextRand(inout uint state)
{
    state ^= (state >> 17);
    state *= 0xed5ad4bbU;
    state ^= (state >> 11);
    state *= 0xac4c1b51U;
    state ^= (state >> 15);
    state *= 0x31848babU;
    state ^= (state >> 14);
    return float(state & 0x00FFFFFFu) / float(0x01000000u); // [0, 1)
}

// Compute shader entry point
[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixelPos = DTid.xy;
    float width = cb.textureDim.x;
    float height = cb.textureDim.y;
    // Check if pixel is within bounds
    if (pixelPos.x >= width || pixelPos.y >= height)
        return;
    
    
    // Load current data
    float4 worldPos = g_rtGBufferPosition[pixelPos];
    
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[pixelPos];
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    // Load current reservoir state
    float4 reservoirWeight = g_ReservoirWeight_In[pixelPos];
    float4 reservoirY = g_ReservoirY_In[pixelPos];
    float4 lightSample = g_LightSample_In[pixelPos];
    float4 lightNormalArea = g_LightNormalArea_In[pixelPos];
    
    // Unpack current reservoir state
    float W_Y = reservoirWeight.x; // Current weight
    float w_sum = reservoirWeight.y; // Sum of weights
    int M = (int) reservoirWeight.z; // Number of samples
    float frameIdx = reservoirWeight.w; // Frame index
    
    // Initialize random seed
    uint seed = initRand(pixelPos.x + pixelPos.y * width, frameIdx, 16);
    
    // Check if this is a valid position (not background)
    if (worldPos.w == 0)
    {
        // Reset reservoir and exit
        g_ReservoirY_Out[pixelPos] = float4(0, 0, 0, 0);
        g_ReservoirWeight_Out[pixelPos] = float4(0, 0, 0, frameIdx);
        g_LightSample_Out[pixelPos] = float4(0, 0, 0, 0);
        g_LightNormalArea_Out[pixelPos] = float4(0, 0, 0, 0);
        return;
    }
    
    int M_sum = M;
    
    // Sample k = 5 random points in a 10-pixel radius around the current pixel
    for (int i = 0; i < 5; i++)
    {
        // Generate a random point within the radius
        float r = 10.0 * sqrt(nextRand(seed));
        float theta = 2.0 * PI * nextRand(seed);
        float2 offset = float2(r * cos(theta), r * sin(theta));
        
        // Calculate pixel position
        int2 neighborPixelPos = int2(pixelPos) + int2(offset);
        
        // Check if neighbor is within screen bounds
        if (neighborPixelPos.x < 0 || neighborPixelPos.x >= width ||
            neighborPixelPos.y < 0 || neighborPixelPos.y >= height)
        {
            continue;
        }
        
        // Fetch neighbor data from global memory
        float4 neighborPos = g_rtGBufferPosition[neighborPixelPos];
        float4 neighborReservoirY = g_ReservoirY_In[neighborPixelPos];
        float4 neighborReservoirWeight = g_ReservoirWeight_In[neighborPixelPos];
        float4 neighborLightSample = g_LightSample_In[neighborPixelPos];
        
        // Skip if neighbor is background
        if (neighborPos.w == 0)
        {
            continue;
        }
        
        NormalDepthTexFormat neighborNormalDepth = g_rtGBufferNormalDepth[neighborPixelPos];
        float3 neighborNormal;
        float neighborDepth;
        DecodeNormalDepth(neighborNormalDepth, neighborNormal, neighborDepth);
        
        // The angle between normals should not exceed 25 degrees (cos(25°) ≈ 0.9063)
        if (dot(worldNormal, neighborNormal) < 0.9063)
        {
            continue;
        }
        
        // Depth check - don't mix samples from significantly different depths
        if (neighborDepth > 1.1 * pixelDepth || neighborDepth < 0.9 * pixelDepth)
        {
            continue;
        }
        
        // Skip if neighbor has no valid sample
        if (neighborReservoirY.w == 0)
        {
            M_sum += (int) neighborReservoirWeight.z; // Add M value
            continue;
        }
        
        // Get the light sample position
        float3 neighborLightPosW = neighborReservoirY.xyz;
        
        // Calculate direction from current pixel to the light sample
        float3 dirToLight = normalize(neighborLightPosW - worldPos.xyz);
        
        // Get the material properties for the current pixel
        float3 albedo = g_rtAOSurfaceAlbedo[pixelPos].xyz;
        
        // Evaluate the PDF for the current pixel
        float p_hat = EvalP(dirToLight, albedo, neighborLightSample.xyz, worldNormal);
        
        // Calculate the weight for this sample
        float w = p_hat * neighborReservoirWeight.x * (int) neighborReservoirWeight.z;
        
        // Update reservoir with this sample
        w_sum += w; // Update w_sum
        
        // Conditionally update the reservoir based on weight
        if (w_sum > 0 && nextRand(seed) < (w / w_sum))
        {
            lightSample = neighborLightSample;
            lightNormalArea = g_LightNormalArea_In[neighborPixelPos];
            reservoirY = float4(neighborLightPosW, 1.0);
        }
        
        M_sum += (int) neighborReservoirWeight.z;
    }
    
    // Update M to include the sum of all considered samples
    M = M_sum;
    
    // Finalize the reservoir
    if (reservoirY.w > 0)
    {
        float3 vecToLight = reservoirY.xyz - worldPos.xyz;
        float distToLight = length(vecToLight);
        
        if (distToLight > 0)
        {
            float3 dirToLight = vecToLight / distToLight;
            
            // Get the material properties for the current pixel
            float3 albedo = g_rtAOSurfaceAlbedo[pixelPos].xyz;
            
            // Evaluate the PDF for the current pixel with the selected sample
            float p_hat_s = EvalP(dirToLight, albedo, lightSample.xyz, worldNormal);
            
            // Calculate the final weight
            if (p_hat_s == 0)
            {
                W_Y = 0;
            }
            else
            {
                W_Y = w_sum / p_hat_s / float(M);
            }
        }
        else
        {
            // Zero distance to light is invalid
            W_Y = 0;
            reservoirY.w = 0;
        }
    }
    else
    {
        // No valid sample
        W_Y = 0;
    }
    
    // Write results back to output textures
    g_ReservoirY_Out[pixelPos] = reservoirY;
    g_ReservoirWeight_Out[pixelPos] = float4(W_Y, w_sum, M, frameIdx);
    g_LightSample_Out[pixelPos] = lightSample;
    g_LightNormalArea_Out[pixelPos] = lightNormalArea;
}
