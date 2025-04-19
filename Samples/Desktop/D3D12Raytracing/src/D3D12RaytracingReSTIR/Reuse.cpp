//*********************************************************
//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
//*********************************************************

#include "Reuse.h"

#include "CompiledShaders\DownsampleGBufferDataBilateralFilter2x2CS.hlsl.h"
#include "CompiledShaders\UpsampleBilateralFilter2x2FloatCS.hlsl.h"
#include "CompiledShaders\UpsampleBilateralFilter2x2UintCS.hlsl.h"
#include "CompiledShaders\UpsampleBilateralFilter2x2Float2CS.hlsl.h"
#include "D3D12RaytracingReSTIR.h"
#include "DirectXRaytracingHelper.h"
#include "EngineProfiling.h"
#include "stdafx.h"

using namespace std;

namespace Reuse {
namespace RootSignature {
namespace SpatialReuse {
namespace Slot {
enum Enum {
  OutputNormal = 0,
  OutputPosition,
  OutputPartialDistanceDerivative,
  OutputMotionVector,
  OutputPrevFrameHitPosition,
  OutputDepth,
  OutputSurfaceAlbedo,
  InputNormal,
  InputPosition,
  InputPartialDistanceDerivative,
  InputMotionVector,
  InputPrevFrameHitPosition,
  InputDepth,
  InputSurfaceAlbedo,
  ConstantBuffer,
  Count
};
}
}  // namespace SpatialReuse
}  // namespace RootSignature

void SpatialReuse::Initialize(ID3D12Device5* device,
                                                      UINT frameCount,
                                                      UINT numCallsPerFrame) {
  // Create root signature.
  {
    using namespace RootSignature::SpatialReuse;

    CD3DX12_DESCRIPTOR_RANGE ranges[Slot::Count];
    ranges[Slot::InputNormal].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                   1);  // 1 input normal texture
    ranges[Slot::InputPosition].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                     2);  // 1 input position texture
    ranges[Slot::InputPartialDistanceDerivative].Init(
        D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
        4);  // 1 input partial distance derivative
    ranges[Slot::OutputNormal].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                    1);  // 1 output normal texture
    ranges[Slot::OutputPosition].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                      2);  // 1 output position texture
    ranges[Slot::OutputPartialDistanceDerivative].Init(
        D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
        4);  // 1 output partial distance derivative
    ranges[Slot::InputDepth].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                  5);  // 1 input depth
    ranges[Slot::OutputDepth].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                   5);  // 1 output depth
    ranges[Slot::InputMotionVector].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                         6);  // 1 input motion vector
    ranges[Slot::OutputMotionVector].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          6);  // 1 output motion vector
    ranges[Slot::InputPrevFrameHitPosition].Init(
        D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
        7);  // 1 input previous frame hit position
    ranges[Slot::OutputPrevFrameHitPosition].Init(
        D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
        7);  // 1 output previous frame hit position
    ranges[Slot::InputSurfaceAlbedo].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                          8);
    ranges[Slot::OutputSurfaceAlbedo].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                           8);

    CD3DX12_ROOT_PARAMETER rootParameters[Slot::Count];
    rootParameters[Slot::InputNormal].InitAsDescriptorTable(
        1, &ranges[Slot::InputNormal]);
    rootParameters[Slot::InputPosition].InitAsDescriptorTable(
        1, &ranges[Slot::InputPosition]);
    rootParameters[Slot::InputPartialDistanceDerivative].InitAsDescriptorTable(
        1, &ranges[Slot::InputPartialDistanceDerivative]);
    rootParameters[Slot::OutputNormal].InitAsDescriptorTable(
        1, &ranges[Slot::OutputNormal]);
    rootParameters[Slot::OutputPosition].InitAsDescriptorTable(
        1, &ranges[Slot::OutputPosition]);
    rootParameters[Slot::OutputPartialDistanceDerivative].InitAsDescriptorTable(
        1, &ranges[Slot::OutputPartialDistanceDerivative]);
    rootParameters[Slot::InputDepth].InitAsDescriptorTable(
        1, &ranges[Slot::InputDepth]);
    rootParameters[Slot::OutputDepth].InitAsDescriptorTable(
        1, &ranges[Slot::OutputDepth]);
    rootParameters[Slot::InputMotionVector].InitAsDescriptorTable(
        1, &ranges[Slot::InputMotionVector]);
    rootParameters[Slot::OutputMotionVector].InitAsDescriptorTable(
        1, &ranges[Slot::OutputMotionVector]);
    rootParameters[Slot::InputPrevFrameHitPosition].InitAsDescriptorTable(
        1, &ranges[Slot::InputPrevFrameHitPosition]);
    rootParameters[Slot::OutputPrevFrameHitPosition].InitAsDescriptorTable(
        1, &ranges[Slot::OutputPrevFrameHitPosition]);
    rootParameters[Slot::InputSurfaceAlbedo].InitAsDescriptorTable(
        1, &ranges[Slot::InputSurfaceAlbedo]);
    rootParameters[Slot::OutputSurfaceAlbedo].InitAsDescriptorTable(
        1, &ranges[Slot::OutputSurfaceAlbedo]);
    rootParameters[Slot::ConstantBuffer].InitAsConstantBufferView(0);

    CD3DX12_STATIC_SAMPLER_DESC staticSamplers[] = {CD3DX12_STATIC_SAMPLER_DESC(
        0, D3D12_FILTER_MIN_MAG_MIP_POINT, D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
        D3D12_TEXTURE_ADDRESS_MODE_CLAMP)};

    CD3DX12_ROOT_SIGNATURE_DESC rootSignatureDesc(
        ARRAYSIZE(rootParameters), rootParameters, ARRAYSIZE(staticSamplers),
        staticSamplers);
    SerializeAndCreateRootSignature(
        device, rootSignatureDesc, &m_rootSignature,
        L"Compute root signature: SpatialReuse");
  }

  // Create compute pipeline state.
  {
    D3D12_COMPUTE_PIPELINE_STATE_DESC descComputePSO = {};
    descComputePSO.pRootSignature = m_rootSignature.Get();
    descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
        static_cast<const void*>(g_pDownsampleGBufferDataBilateralFilter2x2CS),
        ARRAYSIZE(g_pDownsampleGBufferDataBilateralFilter2x2CS));

    ThrowIfFailed(device->CreateComputePipelineState(
        &descComputePSO, IID_PPV_ARGS(&m_pipelineStateObject)));
    m_pipelineStateObject->SetName(
        L"Pipeline state object: SpatialReuse");
  }

  // Create shader resources
  {
    m_CB.Create(device, frameCount * numCallsPerFrame,
                L"Constant Buffer: SpatialReuse");
  }
}

// Downsamples input resource.
// width, height - dimensions of the input resource.
void SpatialReuse::Run(
    ID3D12GraphicsCommandList4* commandList, UINT width, UINT height,
    ID3D12DescriptorHeap* descriptorHeap,
    D3D12_GPU_DESCRIPTOR_HANDLE inputNormalResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputPositionResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputPartialDistanceDerivativesResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputMotionVectorResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputPrevFrameHitPositionResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputDepthResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputSurfaceAlbedoResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputNormalResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputPositionResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputPartialDistanceDerivativesResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputMotionVectorResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputPrevFrameHitPositionResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputDepthResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputSurfaceAlbedoResourceHandle) {
  using namespace RootSignature::SpatialReuse;
  using namespace DefaultComputeShaderParams;

  ScopedTimer _prof(L"SpatialReuse", commandList);

  m_CB->textureDim = XMUINT2(width, height);
  m_CB->invTextureDim = XMFLOAT2(1.f / width, 1.f / height);
  m_CBinstanceID = (m_CBinstanceID + 1) % m_CB.NumInstances();
  m_CB.CopyStagingToGpu(m_CBinstanceID);

  // Set pipeline state.
  {
    commandList->SetDescriptorHeaps(1, &descriptorHeap);
    commandList->SetComputeRootSignature(m_rootSignature.Get());
    commandList->SetComputeRootDescriptorTable(Slot::InputNormal,
                                               inputNormalResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::InputPosition,
                                               inputPositionResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::InputPartialDistanceDerivative,
        inputPartialDistanceDerivativesResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::InputMotionVector,
                                               inputMotionVectorResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::InputPrevFrameHitPosition,
        inputPrevFrameHitPositionResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::InputDepth,
                                               inputDepthResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::InputSurfaceAlbedo, inputSurfaceAlbedoResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::OutputNormal,
                                               outputNormalResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::OutputPosition,
                                               outputPositionResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::OutputPartialDistanceDerivative,
        outputPartialDistanceDerivativesResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::OutputMotionVector, outputMotionVectorResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::OutputPrevFrameHitPosition,
        outputPrevFrameHitPositionResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::OutputDepth,
                                               outputDepthResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::OutputSurfaceAlbedo, outputSurfaceAlbedoResourceHandle);
    commandList->SetComputeRootConstantBufferView(
        Slot::ConstantBuffer, m_CB.GpuVirtualAddress(m_CBinstanceID));
    commandList->SetPipelineState(m_pipelineStateObject.Get());
  }

  XMUINT2 groupSize(CeilDivide((width + 1) / 2 + 1, ThreadGroup::Width),
                    CeilDivide((height + 1) / 2 + 1, ThreadGroup::Height));

  // Dispatch.
  commandList->Dispatch(groupSize.x, groupSize.y, 1);
}

namespace RootSignature {
namespace TemporalReuse {
namespace Slot {
enum Enum {
  Output = 0,
  Input,
  InputLowResNormal,
  InputHiResNormal,
  InputHiResPartialDistanceDerivative,
  Debug1,
  Debug2,
  ConstantBuffer,
  Count
};
}
}  // namespace TemporalReuse
}  // namespace RootSignature

void TemporalReuse::Initialize(ID3D12Device5* device, UINT frameCount,
                                         UINT numCallsPerFrame) {
  // Create root signature.
  {
    using namespace RootSignature::TemporalReuse;

    CD3DX12_DESCRIPTOR_RANGE ranges[Slot::Count];
    ranges[Slot::Input].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                             0);  // 1 input texture
    ranges[Slot::InputLowResNormal].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                         1);  // 1 input normal low res texture
    ranges[Slot::InputHiResNormal].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                        2);  // 1 input normal high res texture
    ranges[Slot::InputHiResPartialDistanceDerivative].Init(
        D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
        3);  // 1 input partial distance derivative texture
    ranges[Slot::Output].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                              0);  // 1 output texture
    ranges[Slot::Debug1].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 1);
    ranges[Slot::Debug2].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 2);

    CD3DX12_ROOT_PARAMETER rootParameters[Slot::Count];
    rootParameters[Slot::Input].InitAsDescriptorTable(1, &ranges[Slot::Input]);
    rootParameters[Slot::InputLowResNormal].InitAsDescriptorTable(
        1, &ranges[Slot::InputLowResNormal]);
    rootParameters[Slot::InputHiResNormal].InitAsDescriptorTable(
        1, &ranges[Slot::InputHiResNormal]);
    rootParameters[Slot::InputHiResPartialDistanceDerivative]
        .InitAsDescriptorTable(
            1, &ranges[Slot::InputHiResPartialDistanceDerivative]);
    rootParameters[Slot::Output].InitAsDescriptorTable(1,
                                                       &ranges[Slot::Output]);
    rootParameters[Slot::Debug1].InitAsDescriptorTable(1,
                                                       &ranges[Slot::Debug1]);
    rootParameters[Slot::Debug2].InitAsDescriptorTable(1,
                                                       &ranges[Slot::Debug2]);
    rootParameters[Slot::ConstantBuffer].InitAsConstantBufferView(0);

    CD3DX12_STATIC_SAMPLER_DESC staticSamplers[] = {CD3DX12_STATIC_SAMPLER_DESC(
        0, D3D12_FILTER_MIN_MAG_MIP_POINT, D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
        D3D12_TEXTURE_ADDRESS_MODE_CLAMP)};

    CD3DX12_ROOT_SIGNATURE_DESC rootSignatureDesc(
        ARRAYSIZE(rootParameters), rootParameters, ARRAYSIZE(staticSamplers),
        staticSamplers);
    SerializeAndCreateRootSignature(
        device, rootSignatureDesc, &m_rootSignature,
        L"Compute root signature: TemporalReuse");
  }

  // Create compute pipeline state.
  {
    D3D12_COMPUTE_PIPELINE_STATE_DESC descComputePSO = {};
    descComputePSO.pRootSignature = m_rootSignature.Get();

    for (UINT i = 0; i < FilterType::Count; i++) {
      switch (i) {
        case Filter2x2FloatR:
          descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
              static_cast<const void*>(g_pUpsampleBilateralFilter2x2FloatCS),
              ARRAYSIZE(g_pUpsampleBilateralFilter2x2FloatCS));
          break;
        case Filter2x2UintR:
          descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
              static_cast<const void*>(g_pUpsampleBilateralFilter2x2UintCS),
              ARRAYSIZE(g_pUpsampleBilateralFilter2x2UintCS));
          break;
        case Filter2x2FloatRG:
          descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
              static_cast<const void*>(g_pUpsampleBilateralFilter2x2Float2CS),
              ARRAYSIZE(g_pUpsampleBilateralFilter2x2Float2CS));
          break;
      }

      ThrowIfFailed(device->CreateComputePipelineState(
          &descComputePSO, IID_PPV_ARGS(&m_pipelineStateObjects[i])));
      m_pipelineStateObjects[i]->SetName(
          L"Pipeline state object: TemporalReuse");
    }
  }

  // Create shader resources
  {
    m_CB.Create(device, frameCount * numCallsPerFrame,
                L"Constant Buffer: GaussianFilter");
  }
}

// Resamples input resource.
// width, height - dimensions of the output resource.
void TemporalReuse::Run(
    ID3D12GraphicsCommandList4* commandList, UINT width, UINT height,
    FilterType type, ID3D12DescriptorHeap* descriptorHeap,
    D3D12_GPU_DESCRIPTOR_HANDLE inputResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputLowResNormalResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE inputHiResNormalResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE
        inputHiResPartialDistanceDerivativeResourceHandle,
    D3D12_GPU_DESCRIPTOR_HANDLE outputResourceHandle) {
  using namespace RootSignature::TemporalReuse;
  using namespace DefaultComputeShaderParams;

  ScopedTimer _prof(L"TemporalReuse", commandList);

  // Each shader execution processes 2x2 hiRes pixels
  XMUINT2 lowResDim = XMUINT2(CeilDivide(width, 2), CeilDivide(height, 2));

  m_CB->invHiResTextureDim = XMFLOAT2(1.f / width, 1.f / height);
  m_CB->invLowResTextureDim = XMFLOAT2(1.f / lowResDim.x, 1.f / lowResDim.y);
  m_CBinstanceID = (m_CBinstanceID + 1) % m_CB.NumInstances();
  m_CB.CopyStagingToGpu(m_CBinstanceID);

  // Set pipeline state.
  {
    commandList->SetDescriptorHeaps(1, &descriptorHeap);
    commandList->SetComputeRootSignature(m_rootSignature.Get());
    commandList->SetComputeRootDescriptorTable(Slot::Input,
                                               inputResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::InputLowResNormal,
                                               inputLowResNormalResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::InputHiResNormal,
                                               inputHiResNormalResourceHandle);
    commandList->SetComputeRootDescriptorTable(
        Slot::InputHiResPartialDistanceDerivative,
        inputHiResPartialDistanceDerivativeResourceHandle);
    commandList->SetComputeRootDescriptorTable(Slot::Output,
                                               outputResourceHandle);
    commandList->SetComputeRootConstantBufferView(
        Slot::ConstantBuffer, m_CB.GpuVirtualAddress(m_CBinstanceID));

    GpuResource* debugResources = Sample::g_debugOutput;
    commandList->SetComputeRootDescriptorTable(
        Slot::Debug1, debugResources[0].gpuDescriptorWriteAccess);
    commandList->SetComputeRootDescriptorTable(
        Slot::Debug2, debugResources[1].gpuDescriptorWriteAccess);

    commandList->SetPipelineState(m_pipelineStateObjects[type].Get());
  }

  // Start from -1,-1 pixel to account for high-res pixel border around low-res
  // pixel border.
  XMUINT2 groupSize(CeilDivide(lowResDim.x + 1, ThreadGroup::Width),
                    CeilDivide(lowResDim.y + 1, ThreadGroup::Height));

  // Dispatch.
  commandList->Dispatch(groupSize.x, groupSize.y, 1);
}


}  // namespace Reuse