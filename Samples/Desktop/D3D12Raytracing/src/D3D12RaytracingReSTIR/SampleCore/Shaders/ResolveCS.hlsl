#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"
#include "BxDF.hlsli"

// Input G-Buffer textures
Texture2D<float4> g_rtGBufferPosition : register(t0); // World space position (xyz) + flag (w)
Texture2D<NormalDepthTexFormat> g_rtGBufferNormalDepth : register(t1); // Normal (xyz) + depth (w)
Texture2D<float4> g_KdRoughness : register(t2);
Texture2D<float4> g_KsType : register(t3);
                                            
// Current reservoirs
Texture2D<float4> g_ReservoirY : register(t4); // xyz: stored sample position, w: hasValue flag (1.0 if valid)
Texture2D<float4> g_ReservoirWeight : register(t5); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
Texture2D<float4> g_LightSample : register(t6); // xyz: light color/intensity, w: not used
Texture2D<float4> g_LightNormalArea : register(t7); // xyz: light normal, w: light area

// Output reservoirs
RWTexture2D<float4> g_PrevReservoirY_Out : register(u0); // xyz: stored sample position, w: hasValue flag
RWTexture2D<float4> g_PrevReservoirWeight_Out : register(u1); // x: W_Y, y: w_sum, z: M (number of samples), w: frame counter
RWTexture2D<float4> g_PrevLightSample_Out : register(u2); // xyz: light color/intensity, w: not used
RWTexture2D<float4> g_PrevLightNormalArea_Out : register(u3); // xyz: light normal, w: light area

RWTexture2D<float4> g_rtColor : register(u4);
                                            
ConstantBuffer<TextureDimConstantBuffer> cb : register(b0);
ConstantBuffer<PathtracerConstantBuffer> g_cb : register(b1);

[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint2 pixelPos : SV_DispatchThreadID)
{
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
    
    MaterialType::Type type = (MaterialType::Type) (g_KsType[pixelPos].w);
    float3 Kd = g_KdRoughness[pixelPos].xyz;
    float3 Ks = g_KsType[pixelPos].xyz;
    float roughness = g_KdRoughness[pixelPos].w;
    
    float3 lightColor = g_LightSample[pixelPos].xyz;
    float3 sampledPosition = g_ReservoirY[pixelPos].xyz;
    float3 lightDir = normalize(sampledPosition - worldPos.xyz);
    
    // Calculate world ray direction using camera position from constant buffer
    float3 V = normalize(g_cb.cameraPosition - worldPos.xyz);
    
    if (dot(-lightDir, g_LightNormalArea[pixelPos].xyz) > 0 && g_ReservoirY[pixelPos].w > 0.5 && g_ReservoirWeight[pixelPos].z > 0.0)
    {
        float3 contribution = BxDF::DirectLighting::Shade(type, Kd, Ks, lightColor, false, roughness, worldNormal, V, lightDir);
        g_rtColor[pixelPos].xyz += contribution * g_ReservoirWeight[pixelPos].x;
    }
    
    g_PrevLightSample_Out[pixelPos] = g_LightSample[pixelPos];
    g_PrevLightNormalArea_Out[pixelPos] = g_LightNormalArea[pixelPos];
    g_PrevReservoirY_Out[pixelPos] = g_ReservoirY[pixelPos];
    g_PrevReservoirWeight_Out[pixelPos] = g_ReservoirWeight[pixelPos];
}