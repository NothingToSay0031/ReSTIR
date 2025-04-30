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
    
     // --- Load Current Pixel Data ---
    float4 worldPos = g_rtGBufferPosition[DTid];

    // --- Background Check ---
    // Reference code does this check (gWsPos[pixelPos].w == 0)
    if (worldPos.w == 0.0f)
    {
        // Write invalid/empty reservoir state
        g_ReservoirY_Out[DTid] = float4(0, 0, 0, 0); // Mark as invalid
        g_ReservoirWeight_Out[DTid] = float4(0, 0, 0, g_ReservoirWeight_In[DTid].w); // W=0, w_sum=0, M=0, keep frameIdx
        g_LightSample_Out[DTid] = float4(0, 0, 0, 0);
        g_LightNormalArea_Out[DTid] = float4(0, 0, 0, 0);
        return;
    }

    int frameIdx = (int) g_ReservoirWeight_In[DTid].w; // Frame index from input reservoir
    uint seed = RNG::SeedThread(DTid.x * 16807 ^ DTid.y * 65539 ^ frameIdx * 48271 ^ (DTid.x + DTid.y + frameIdx) * 22801);
    // --- Initialize NEW Output Reservoir (Empty) ---
    float4 outY = float4(0.0f, 0.0f, 0.0f, 0.0f); // Initialize as invalid (.w = 0)
    float4 outLightSample = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float4 outLightNormalArea = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float outWsum = 0.0f;
    int outM = 0;
    // float final_W will be calculated at the end

    // --- Load Current Pixel's Geometric Data ---
    float3 worldPosXYZ = g_rtGBufferPosition[DTid.xy].xyz;
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(g_rtGBufferNormalDepth[DTid.xy], worldNormal, pixelDepth);
    float3 diffuseAlbedo = g_rtAOSurfaceAlbedo[DTid.xy].xyz; // Diffuse albedo (Kd) from G-buffer]
    
    uint width = cb.textureDim.x;
    uint height = cb.textureDim.y;
    // --- Process Current Pixel's Reservoir (First Contribution) ---
    float4 currentY = g_ReservoirY_In[DTid.xy];
    if (currentY.w > 0.5f) // Check if the current pixel's input reservoir is valid
    {
        float4 currentWeight = g_ReservoirWeight_In[DTid.xy];
        float4 currentLightSample = g_LightSample_In[DTid.xy];
        float4 currentLightNormalArea = g_LightNormalArea_In[DTid.xy];

        float currentW = currentWeight.x;
        int currentM = max(1, (int) currentWeight.z); // M should be at least 1 if valid

        // Calculate the PDF of the current pixel's sample evaluated at the current pixel itself
        float3 dirToCurrentLight = normalize(currentY.xyz - worldPosXYZ);
        float p_hat_current = EvalP(dirToCurrentLight, diffuseAlbedo, currentLightSample.xyz, worldNormal);

        // Calculate the weight for combining this reservoir's sample
        float w_current_combine = p_hat_current * currentW * (float) currentM;
        int tempM = currentM;
        // Update the (initially empty) output reservoir with the current pixel's data
        // Since it's the first contribution, it will always be selected if w_current_combine > 0
        UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, tempM,
                        currentY, currentLightSample, currentLightNormalArea, w_current_combine, seed);

        // Add the number of samples from the current pixel's reservoir
        outM += currentM;
    }
    // If currentY.w <= 0.5f, the current pixel doesn't contribute initially. outM remains 0.

    // --- Pre-compute Spatial Reuse Constants ---
    const float normalThreshold = 0.9063; // cos(25 degrees)
    const float depthThresholdRelative = 0.1; // Relative depth threshold (10%)
    const int SAMPLES = 5; // Number of spatial neighbors to check
    const float RADIUS = 10.0; // Search radius in pixels
    const int2 iBOUNDS = int2(width, height) - 1; // Use int bounds for clamping
    
    // --- Iterate Through Spatial Neighbors ---
    [unroll(SAMPLES)]
    for (int i = 0; i < SAMPLES; i++)
    {
        // Generate neighbor sampling point
        float r = RADIUS * sqrt(RNG::Random01inclusive(seed));
        float theta = 2.0 * 3.14159 * RNG::Random01(seed);
        // Calculate offset and add to current pixel coordinates
        float2 offset = float2(r * cos(theta), r * sin(theta));
        int2 neighborDTid = int2(round(float(DTid.x) + offset.x), round(float(DTid.y) + offset.y));

        // Clamp neighbor coordinates to texture bounds
        neighborDTid = clamp(neighborDTid, int2(0, 0), iBOUNDS);

        // Skip self-sampling explicitly (though clamping might handle some cases)
        if (neighborDTid.x == DTid.x && neighborDTid.y == DTid.y)
        {
            continue;
        }

        // --- Neighbor Geometric Validity Checks ---
        float3 neighborNormal;
        float neighborDepth;
        DecodeNormalDepth(g_rtGBufferNormalDepth[neighborDTid], neighborNormal, neighborDepth);

        // Normal check
        if (dot(worldNormal, neighborNormal) < normalThreshold)
        {
            continue;
        }

        // Depth check
        if (abs(neighborDepth - pixelDepth) > depthThresholdRelative * pixelDepth)
        {
            continue;
        }

        // --- Neighbor Reservoir Validity and Combination ---
        float4 neighborY = g_ReservoirY_In[neighborDTid];

        // Check if the neighbor's reservoir itself is valid
        if (neighborY.w < 0.5f)
        {
            continue; // Skip invalid neighbor reservoirs
        }

        // Load remaining neighbor reservoir data
        float4 neighborWeight = g_ReservoirWeight_In[neighborDTid];
        float4 neighborLightSample = g_LightSample_In[neighborDTid];
        float4 neighborLightNormalArea = g_LightNormalArea_In[neighborDTid];

        // Extract neighbor stats
        float neighborW = neighborWeight.x;
        int neighborM = max(1, (int) neighborWeight.z); // M should be at least 1 if valid

        // Calculate the PDF of the neighbor's sample evaluated at the *current* pixel
        float3 dirToNeighborLight = normalize(neighborY.xyz - worldPosXYZ);
        float p_hat_neighbor = EvalP(dirToNeighborLight, diffuseAlbedo, neighborLightSample.xyz, worldNormal);

        // Calculate the weight for combining this neighbor's reservoir
        float w_neighbor_combine = p_hat_neighbor * neighborW * (float) neighborM;
        int tempM = neighborM;
        // Update the output reservoir by potentially merging the neighbor's sample
        UpdateReservoir(outY, outLightSample, outLightNormalArea, outWsum, tempM,
                        neighborY, neighborLightSample, neighborLightNormalArea, w_neighbor_combine, seed);

        // Accumulate the number of samples seen from the neighbor
        outM += neighborM;

    } // End spatial neighbor loop

    // --- Finalize Output Reservoir Weight ---
    float final_W = 0.0f;
    if (outY.w > 0.5f && outM > 0) // Check if a valid sample exists in the output and M > 0
    {
        // Calculate the PDF of the *final chosen sample* (stored in outY) evaluated at the current pixel
        float3 dirToFinalLight = normalize(outY.xyz - worldPosXYZ);
        float p_hat_final = EvalP(dirToFinalLight, diffuseAlbedo, outLightSample.xyz, worldNormal);

        // Calculate the final weight W = w_sum / (M * p_hat)
        if (abs(p_hat_final) > 1e-6f)
        {
            final_W = outWsum / (p_hat_final * (float) outM);
        }
        else
        {
            // If p_hat is zero for the final sample, the reservoir becomes invalid for this pixel
            final_W = 0.0f;
            outY.w = 0.0f; // Mark the reservoir as invalid
            outWsum = 0.0f;
             // Keep outM as the count of samples considered, even if the final one was bad
        }
    }
    else
    {
        // If no valid sample ended up in the reservoir (e.g., started invalid and all neighbors were invalid/rejected)
        final_W = 0.0f;
        outWsum = 0.0f;
        outY.w = 0.0f; // Ensure invalidity is marked
        // If outY is invalid, outM should logically be 0 as no valid sample represents the stream.
        if (outY.w < 0.5f)
            outM = 0;
    }


    // --- Write Output ---
    g_ReservoirY_Out[DTid.xy] = outY; // Final chosen sample position (and validity in .w)
    g_ReservoirWeight_Out[DTid.xy] = float4(final_W, outWsum, (float) outM, outY.w); // Store final W, Wsum, M, and validity
    g_LightSample_Out[DTid.xy] = outLightSample; // Final chosen light sample properties
    g_LightNormalArea_Out[DTid.xy] = outLightNormalArea; // Final chosen light normal/area
}