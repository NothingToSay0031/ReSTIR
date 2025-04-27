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
void main(uint2 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= cb.textureDim.x || DTid.y >= cb.textureDim.y)
        return;
    
    float4 worldPos = g_rtGBufferPosition[DTid];
    NormalDepthTexFormat normalDepth = g_rtGBufferNormalDepth[DTid];
    float4 kdRoughness = g_KdRoughness[DTid];
    float4 ksType = g_KsType[DTid];
    
    float4 reservoirY = g_ReservoirY[DTid];
    float4 lightSample = g_LightSample[DTid];
    float4 lightNormalArea = g_LightNormalArea[DTid];
    float4 reservoirWeight = g_ReservoirWeight[DTid];
    
    float3 worldNormal;
    float pixelDepth;
    DecodeNormalDepth(normalDepth, worldNormal, pixelDepth);
    
    MaterialType::Type type = (MaterialType::Type) (ksType.w);
    float3 Kd = kdRoughness.xyz;
    float roughness = kdRoughness.w;
    float3 Ks = ksType.xyz;
    
    float3 sampledPosition = reservoirY.xyz;
    float3 contribution = float3(0, 0, 0);
    
    float3 V = normalize(g_cb.cameraPosition - worldPos.xyz);
    
    if (reservoirY.w > 0.5 && reservoirWeight.z > 0.0)
    {
        float3 lightDir = normalize(sampledPosition - worldPos.xyz);
        
        if (dot(-lightDir, lightNormalArea.xyz) > 0)
        {
            float distanceSquared = dot(sampledPosition - worldPos.xyz, sampledPosition - worldPos.xyz);
            float3 lightColor = lightSample.xyz / distanceSquared;
            
            contribution = BxDF::DirectLighting::Shade(
                type, Kd, Ks, lightColor, false, roughness, worldNormal, V, lightDir);
                
            contribution *= reservoirWeight.x;
        }
    }
    
    g_rtColor[DTid].xyz += contribution;
    g_PrevLightSample_Out[DTid] = lightSample;
    g_PrevLightNormalArea_Out[DTid] = lightNormalArea;
    g_PrevReservoirY_Out[DTid] = reservoirY;
    g_PrevReservoirWeight_Out[DTid] = reservoirWeight;
}