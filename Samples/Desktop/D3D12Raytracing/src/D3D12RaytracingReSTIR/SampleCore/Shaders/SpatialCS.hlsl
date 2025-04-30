#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"
#include "RandomNumberGenerator.hlsli"

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
ConstantBuffer<PathtracerConstantBuffer> g_cb : register(b1);

// Optimized version of EvalP function
float EvalP(float3 toLight, float3 diffuse, float3 radiance, float3 normal)
{
    float NdotL = max(0.0, dot(toLight, normal));
    // Combined diffuse BRDF calculation with radiance and NdotL in one step
    float3 color = diffuse * radiance * NdotL * (1.0f / PI);
    return length(color); // scalar pdf target
}

// Compute shader entry point
[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    if ((g_cb.restirMode & 0x01) == 0) {
        g_ReservoirY_Out[DTid] = g_ReservoirY_In[DTid];
        g_ReservoirWeight_Out[DTid] = g_ReservoirWeight_In[DTid];
        g_LightSample_Out[DTid] = g_LightSample_In[DTid];
        g_LightNormalArea_Out[DTid] = g_LightNormalArea_In[DTid];
        return; // Skip if not in spatial mode
    }
    // Fast boundary check
    if (DTid.x >= cb.textureDim.x || DTid.y >= cb.textureDim.y)
        return;
    
    // Load current pixel data
    float4 worldPos = g_rtGBufferPosition[DTid];
    
    // Early background check - return early to avoid unnecessary processing
    if (worldPos.w == 0.0f)
    {
        // Batch reset and return
        uint frameIdx = g_ReservoirWeight_In[DTid].w; // Only read frame index
        float4 zeroVec = float4(0, 0, 0, 0);
        g_ReservoirY_Out[DTid] = zeroVec;
        g_ReservoirWeight_Out[DTid] = float4(0, 0, 0, frameIdx);
        g_LightSample_Out[DTid] = zeroVec;
        g_LightNormalArea_Out[DTid] = zeroVec;
        return;
    }
    
    // Decode normal and depth - do this only once
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[DTid];
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    // Pre-load albedo to avoid multiple accesses in the loop
    float3 albedo = g_rtAOSurfaceAlbedo[DTid].xyz;
    
    // Load current reservoir state at once
    float4 reservoirWeight = g_ReservoirWeight_In[DTid];
    float4 reservoirY = g_ReservoirY_In[DTid];
    float4 lightSample = g_LightSample_In[DTid];
    float4 lightNormalArea = g_LightNormalArea_In[DTid];
    
    // Unpack reservoir state
    float W_Y = reservoirWeight.x; // Current weight
    float w_sum = reservoirWeight.y; // Sum of weights
    int M = (int) reservoirWeight.z; // Number of samples
    uint frameIdx = reservoirWeight.w; // Frame index
    int M_sum = M;
    
    // Initialize random seed
    uint seed = RNG::SeedThread(DTid.x * 19349663 ^ DTid.y * 73856093 ^ frameIdx * 83492791);
    
    // Pre-compute constant values
    const float normalThreshold = 0.9063; // cos(25°)
    const float depthThresholdMin = 0.9;
    const float depthThresholdMax = 1.1;
    const int SAMPLES = 5;
    const float RADIUS = 10.0;
    const float2 BOUNDS = float2(cb.textureDim.x, cb.textureDim.y) - 1;
    
    // Create local cache for values that might be used multiple times
    float3 worldPosXYZ = worldPos.xyz;
    
    // Sample neighboring pixels - use compact loop
    [unroll(SAMPLES)]
    for (int i = 0; i < SAMPLES; i++)
    {
        // Generate neighbor sampling point
        float r = RADIUS * sqrt(RNG::Random01inclusive(seed));
        float theta = 2.0 * PI * RNG::Random01(seed);
        int2 neighborDTid = int2(DTid) + int2(r * cos(theta), r * sin(theta));
        
        // Boundary check - use bit operations and bounds constants
        if (any(neighborDTid < 0) || any(neighborDTid > BOUNDS))
            continue;
        
        // Get neighbor data
        float4 neighborPos = g_rtGBufferPosition[neighborDTid];
        
        // Background check
        if (neighborPos.w == 0)
            continue;
        
        // Decode neighbor normal and depth
        NormalDepthTexFormat neighborNormalDepth = g_rtGBufferNormalDepth[neighborDTid];
        float3 neighborNormal;
        float neighborDepth;
        DecodeNormalDepth(neighborNormalDepth, neighborNormal, neighborDepth);
        
        // Normal and depth check - use parallel comparisons
        bool isValidNeighbor =
            dot(worldNormal, neighborNormal) >= normalThreshold &&
            neighborDepth <= pixelDepth * depthThresholdMax &&
            neighborDepth >= pixelDepth * depthThresholdMin;
            
        if (!isValidNeighbor)
        {
            continue;
        }
        
        // Get neighbor reservoir data
        float4 neighborReservoirY = g_ReservoirY_In[neighborDTid];
        
        // Check sample validity
        if (neighborReservoirY.w < 0.5f)
        {
            float4 neighborReservoirWeight = g_ReservoirWeight_In[neighborDTid];
            M_sum += (int) neighborReservoirWeight.z;
            continue;
        }
        
        // Now fetch more neighbor data - only when needed
        float4 neighborReservoirWeight = g_ReservoirWeight_In[neighborDTid];
        float4 neighborLightSample = g_LightSample_In[neighborDTid];
        
        // Calculate light direction and PDF
        float3 neighborLightPosW = neighborReservoirY.xyz;
        float3 dirToLight = normalize(neighborLightPosW - worldPosXYZ);
        
        // Evaluate PDF for the current pixel
        float p_hat = EvalP(dirToLight, albedo, neighborLightSample.xyz, worldNormal);
        
        // Calculate the weight for this sample
        float w = p_hat * neighborReservoirWeight.x * (float) ((int) neighborReservoirWeight.z);
        
        // Update reservoir
        w_sum += w;
        
        // Conditionally update the reservoir if weight is large enough
        bool shouldUpdate = w_sum > 0 && RNG::Random01(seed) < (w / w_sum);
        if (shouldUpdate)
        {
            lightSample = neighborLightSample;
            lightNormalArea = g_LightNormalArea_In[neighborDTid];
            reservoirY = float4(neighborLightPosW, 1.0);
        }
        
        M_sum += (int) neighborReservoirWeight.z;
    }
    
    // Update M to include the sum of all considered samples
    M = M_sum;
    
    // Finalize reservoir
    if (reservoirY.w > 0.5f)
    {
        float3 vecToLight = reservoirY.xyz - worldPosXYZ;
        float distToLight = length(vecToLight);
        
        if (distToLight > 0)
        {
            float3 dirToLight = vecToLight / distToLight;
            
            // Evaluate PDF for the current pixel with the selected sample
            float p_hat_s = EvalP(dirToLight, albedo, lightSample.xyz, worldNormal);
            
            // Calculate final weight
            W_Y = (abs(p_hat_s) < 1e-5) ? 0.0 : (w_sum / (p_hat_s * (float) M));
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
    g_ReservoirY_Out[DTid] = reservoirY;
    g_ReservoirWeight_Out[DTid] = float4(W_Y, w_sum, M, frameIdx);
    g_LightSample_Out[DTid] = lightSample;
    g_LightNormalArea_Out[DTid] = lightNormalArea;
}