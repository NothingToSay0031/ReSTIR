#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"
#include "BxDF.hlsli"

// Input G-Buffer textures
Texture2D<float4> g_rtGBufferPosition : register(t0); // World space position (xyz) + flag (w)
Texture2D<NormalDepthTexFormat> g_rtGBufferNormalDepth : register(t1); // Normal (xyz) + depth (w)
Texture2D<float4> g_rtAOSurfaceAlbedo : register(t2); // Surface albedo/material diffuse
Texture2D<uint> g_MaterialID : register(t3);
                                            
// Current reservoirs
Texture2D<float4> g_ReservoirY : register(t4); // xyz: stored sample position, w: hasValue flag (1.0 if valid)
Texture2D<float4> g_ReservoirWeight : register(t5); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
Texture2D<float4> g_LightSample : register(t6); // xyz: light color/intensity, w: not used
Texture2D<float4> g_LightNormalArea : register(t7); // xyz: light normal, w: light area

StructuredBuffer<PrimitiveMaterialBuffer> g_materials : register(t8);

// Output reservoirs
RWTexture2D<float4> g_PrevReservoirY_Out : register(u0); // xyz: stored sample position, w: hasValue flag
RWTexture2D<float4> g_PrevReservoirWeight_Out : register(u1); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
RWTexture2D<float4> g_PrevLightSample_Out : register(u2); // xyz: light color/intensity, w: not used
RWTexture2D<float4> g_PrevLightNormalArea_Out : register(u3); // xyz: light normal, w: light area

RWTexture2D<float4> g_rtColor : register(u4);
                                            
ConstantBuffer<TextureDimConstantBuffer> cb : register(b0);
ConstantBuffer<PathtracerConstantBuffer> g_cb : register(b1);

// Compute shader equivalent of WorldRayDirection()
float3 CalculateWorldRayDirection(float3 worldPos, float3 cameraPos)
{
    return normalize(worldPos - cameraPos);
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
    
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[pixelPos];
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    float3 diffuse = g_rtAOSurfaceAlbedo[pixelPos].rgb;
    
    UINT materialID = g_MaterialID[pixelPos];
    //PrimitiveMaterialBuffer material = g_materials[materialID];
    
    //const float3 Kd = material.Kd;
    //const float3 Ks = material.Ks;
    //const float roughness = material.roughness;
    float3 lightColor = g_LightSample[DTid].xyz;
    
    float3 sampledPosition = g_ReservoirY[DTid].xyz;
    
    float3 lightDir = normalize(sampledPosition - worldPos.xyz);
    
    // Calculate world ray direction using camera position from constant buffer
    float3 V = -CalculateWorldRayDirection(worldPos.xyz, g_cb.cameraPosition);
    
    //float3 contribution = BxDF::DirectLighting::Shade(material.type, Kd, Ks, lightColor, false, roughness, worldNormal, V, lightDir);
    float3 contribution = lightColor*10;
    g_rtColor[pixelPos].xyz += contribution * g_ReservoirWeight[pixelPos].x;
            
    g_PrevLightSample_Out[pixelPos] = g_LightSample[pixelPos];
    g_PrevLightNormalArea_Out[pixelPos] = g_LightNormalArea[pixelPos];
    g_PrevReservoirY_Out[pixelPos] = g_ReservoirY[pixelPos];
    g_PrevReservoirWeight_Out[pixelPos] = g_ReservoirWeight[pixelPos];
}