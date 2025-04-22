#define HLSL

#include "RaytracingHlslCompat.h"
#include "RaytracingShaderHelper.hlsli"

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


[numthreads(DefaultComputeShaderParams::ThreadGroup::Width, DefaultComputeShaderParams::ThreadGroup::Height, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    g_ReservoirY_Out[DTid] = g_ReservoirY_In[DTid];
    g_ReservoirWeight_Out[DTid] = g_ReservoirWeight_In[DTid];
    g_LightNormalArea_Out[DTid] = g_LightNormalArea_In[DTid];
    g_LightSample_Out[DTid] = g_LightSample_In[DTid];
}