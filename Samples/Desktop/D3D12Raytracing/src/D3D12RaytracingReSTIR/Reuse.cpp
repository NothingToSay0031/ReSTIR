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

#include "CompiledShaders\ResolveCS.hlsl.h"
#include "CompiledShaders\SpatialCS.hlsl.h"
#include "CompiledShaders\TemporalCS.hlsl.h"
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
  GBufferPosition = 0,
  GBufferNormalDepth,
  AOSurfaceAlbedo,
  ReservoirYIn,
  ReservoirWeightIn,
  LightSampleIn,
  LightNormalAreaIn,
  ReservoirYOut,
  ReservoirWeightOut,
  LightSampleOut,
  LightNormalAreaOut,
  ConstantBuffer,
  Count
};
}
}  // namespace SpatialReuse
}  // namespace RootSignature

void SpatialReuse::Initialize(ID3D12Device5* device, UINT frameCount,
                              UINT numCallsPerFrame) {
  // Create root signature.
  {
    using namespace RootSignature::SpatialReuse;

    CD3DX12_DESCRIPTOR_RANGE ranges[Slot::Count];
    ranges[Slot::GBufferPosition].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 0);
    ranges[Slot::GBufferNormalDepth].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                          1);
    ranges[Slot::AOSurfaceAlbedo].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 2);
    ranges[Slot::ReservoirYIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 3);
    ranges[Slot::ReservoirWeightIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 4);
    ranges[Slot::LightSampleIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 5);
    ranges[Slot::LightNormalAreaIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 6);
    ranges[Slot::ReservoirYOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 0);
    ranges[Slot::ReservoirWeightOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          1);
    ranges[Slot::LightSampleOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 2);
    ranges[Slot::LightNormalAreaOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          3);

    CD3DX12_ROOT_PARAMETER rootParameters[Slot::Count];
    for (int i = 0; i < Slot::Count - 1; ++i) {
      rootParameters[i].InitAsDescriptorTable(1, &ranges[i]);
    }

    rootParameters[Slot::ConstantBuffer].InitAsConstantBufferView(0);

    CD3DX12_ROOT_SIGNATURE_DESC rootSignatureDesc(ARRAYSIZE(rootParameters),
                                                  rootParameters);
    SerializeAndCreateRootSignature(device, rootSignatureDesc, &m_rootSignature,
                                    L"Compute root signature: SpatialReuse");
  }

  // Create compute pipeline state.
  {
    D3D12_COMPUTE_PIPELINE_STATE_DESC descComputePSO = {};
    descComputePSO.pRootSignature = m_rootSignature.Get();
    descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
        static_cast<const void*>(g_pSpatialCS), ARRAYSIZE(g_pSpatialCS));
    ThrowIfFailed(device->CreateComputePipelineState(
        &descComputePSO, IID_PPV_ARGS(&m_pipelineStateObject)));
    m_pipelineStateObject->SetName(L"Pipeline state object: SpatialReuse");
  }

  // Create shader resources
  {
    m_CB.Create(device, frameCount * numCallsPerFrame,
                L"Constant Buffer: SpatialReuse");
  }
}

void SpatialReuse::Run(ID3D12GraphicsCommandList4* commandList,
                       ID3D12DescriptorHeap* descriptorHeap, UINT width,
                       UINT height,
                       D3D12_GPU_DESCRIPTOR_HANDLE gBufferPositionHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE gBufferNormalDepthHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE aoSurfaceAlbedoHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE reservoirYInHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE reservoirWeightInHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE lightSampleInHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaInHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE reservoirYOutHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE reservoirWeightOutHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE lightSampleOutHandle,
                       D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaOutHandle) {
  using namespace RootSignature::SpatialReuse;
  using namespace DefaultComputeShaderParams;

  ScopedTimer _prof(L"SpatialReuse", commandList);

  // Update the Constant Buffer.
  {
    m_CB->textureDim = XMUINT2(width, height);
    m_CBinstanceID = (m_CBinstanceID + 1) % m_CB.NumInstances();
    m_CB.CopyStagingToGpu(m_CBinstanceID);
  }

  // Set pipeline state.
  {
    commandList->SetDescriptorHeaps(1, &descriptorHeap);
    commandList->SetComputeRootSignature(m_rootSignature.Get());
    commandList->SetComputeRootDescriptorTable(Slot::GBufferPosition,
                                               gBufferPositionHandle);
    commandList->SetComputeRootDescriptorTable(Slot::GBufferNormalDepth,
                                               gBufferNormalDepthHandle);
    commandList->SetComputeRootDescriptorTable(Slot::AOSurfaceAlbedo,
                                               aoSurfaceAlbedoHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirYIn,
                                               reservoirYInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirWeightIn,
                                               reservoirWeightInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightSampleIn,
                                               lightSampleInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightNormalAreaIn,
                                               lightNormalAreaInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirYOut,
                                               reservoirYOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirWeightOut,
                                               reservoirWeightOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightSampleOut,
                                               lightSampleOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightNormalAreaOut,
                                               lightNormalAreaOutHandle);
    commandList->SetComputeRootConstantBufferView(
        Slot::ConstantBuffer, m_CB.GpuVirtualAddress(m_CBinstanceID));
    commandList->SetPipelineState(m_pipelineStateObject.Get());
  }
  // Dispatch.
  {
    XMUINT2 groupSize(CeilDivide(width, ThreadGroup::Width),
                      CeilDivide(height, ThreadGroup::Height));
    commandList->Dispatch(groupSize.x, groupSize.y, 1);
  }
}

namespace RootSignature {

namespace TemporalReuse {
namespace Slot {
enum Enum {
  GBufferPosition = 0,
  GBufferNormalDepth,
  AOSurfaceAlbedo,
  PrevReservoirYIn,
  PrevReservoirWeightIn,
  PrevLightSampleIn,
  PrevLightNormalAreaIn,
  ReservoirYIn,
  ReservoirWeightIn,
  LightSampleIn,
  LightNormalAreaIn,
  ReservoirYOut,
  ReservoirWeightOut,
  LightSampleOut,
  LightNormalAreaOut,
  ConstantBuffer,
  GlobalConstantBuffer,
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
    ranges[Slot::GBufferPosition].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 0);
    ranges[Slot::GBufferNormalDepth].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                          1);
    ranges[Slot::AOSurfaceAlbedo].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 2);
    ranges[Slot::PrevReservoirYIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 3);
    ranges[Slot::PrevReservoirWeightIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                             4);
    ranges[Slot::PrevLightSampleIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 5);
    ranges[Slot::PrevLightNormalAreaIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                             6);
    ranges[Slot::ReservoirYIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 7);
    ranges[Slot::ReservoirWeightIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 8);
    ranges[Slot::LightSampleIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 9);
    ranges[Slot::LightNormalAreaIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                         10);
    ranges[Slot::ReservoirYOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 0);
    ranges[Slot::ReservoirWeightOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          1);
    ranges[Slot::LightSampleOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 2);
    ranges[Slot::LightNormalAreaOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          3);

    CD3DX12_ROOT_PARAMETER rootParameters[Slot::Count];
    for (int i = 0; i < Slot::Count - 1; ++i) {
      rootParameters[i].InitAsDescriptorTable(1, &ranges[i]);
    }

    rootParameters[Slot::ConstantBuffer].InitAsConstantBufferView(0);
    rootParameters[Slot::GlobalConstantBuffer].InitAsConstantBufferView(1);

    CD3DX12_ROOT_SIGNATURE_DESC rootSignatureDesc(ARRAYSIZE(rootParameters),
                                                  rootParameters);
    SerializeAndCreateRootSignature(device, rootSignatureDesc, &m_rootSignature,
                                    L"Compute root signature: TemporalReuse");
  }

  // Create compute pipeline state.
  {
    D3D12_COMPUTE_PIPELINE_STATE_DESC descComputePSO = {};
    descComputePSO.pRootSignature = m_rootSignature.Get();
    descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
        static_cast<const void*>(g_pTemporalCS), ARRAYSIZE(g_pTemporalCS));
    ThrowIfFailed(device->CreateComputePipelineState(
        &descComputePSO, IID_PPV_ARGS(&m_pipelineStateObject)));
    m_pipelineStateObject->SetName(L"Pipeline state object: TemporalReuse");
  }

  // Create shader resources
  {
    m_CB.Create(device, frameCount * numCallsPerFrame,
                L"Constant Buffer: TemporalReuse");
  }
}

void TemporalReuse::Run(ID3D12GraphicsCommandList4* commandList, UINT width,
                        UINT height, ID3D12DescriptorHeap* descriptorHeap,
                        D3D12_GPU_DESCRIPTOR_HANDLE gBufferPositionHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE gBufferNormalDepthHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE aoSurfaceAlbedoHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE prevReservoirYInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE prevReservoirWeightInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE prevLightSampleInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE prevLightNormalAreaInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE reservoirYInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE reservoirWeightInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE lightSampleInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaInHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE reservoirYOutHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE reservoirWeightOutHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE lightSampleOutHandle,
                        D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaOutHandle,
                        ConstantBuffer<PathtracerConstantBuffer>& globalCB) {
  using namespace RootSignature::TemporalReuse;
  using namespace DefaultComputeShaderParams;

  ScopedTimer _prof(L"TemporalReuse", commandList);
  // Update the Constant Buffer.
  {
    m_CB->textureDim = XMUINT2(width, height);
    m_CB->invTextureDim = XMFLOAT2(1.f / width, 1.f / height);
    m_CBinstanceID = (m_CBinstanceID + 1) % m_CB.NumInstances();
    m_CB.CopyStagingToGpu(m_CBinstanceID);
  }

  // Set pipeline state and root signature.
  {
    commandList->SetDescriptorHeaps(1, &descriptorHeap);
    commandList->SetComputeRootSignature(m_rootSignature.Get());
    commandList->SetComputeRootDescriptorTable(Slot::GBufferPosition,
                                               gBufferPositionHandle);
    commandList->SetComputeRootDescriptorTable(Slot::GBufferNormalDepth,
                                               gBufferNormalDepthHandle);
    commandList->SetComputeRootDescriptorTable(Slot::AOSurfaceAlbedo,
                                               aoSurfaceAlbedoHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevReservoirYIn,
                                               prevReservoirYInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevReservoirWeightIn,
                                               prevReservoirWeightInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevLightSampleIn,
                                               prevLightSampleInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevLightNormalAreaIn,
                                               prevLightNormalAreaInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirYIn,
                                               reservoirYInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirWeightIn,
                                               reservoirWeightInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightSampleIn,
                                               lightSampleInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightNormalAreaIn,
                                               lightNormalAreaInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirYOut,
                                               reservoirYOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirWeightOut,
                                               reservoirWeightOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightSampleOut,
                                               lightSampleOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightNormalAreaOut,
                                               lightNormalAreaOutHandle);
    commandList->SetComputeRootConstantBufferView(
        Slot::ConstantBuffer, m_CB.GpuVirtualAddress(m_CBinstanceID));
    commandList->SetComputeRootConstantBufferView(
        Slot::GlobalConstantBuffer,
        globalCB.GpuVirtualAddress(globalCB->frameIndex));
    commandList->SetPipelineState(m_pipelineStateObject.Get());
  }

  // Dispatch compute shader.
  {
    XMUINT2 groupSize(CeilDivide(width, ThreadGroup::Width),
                      CeilDivide(height, ThreadGroup::Height));
    commandList->Dispatch(groupSize.x, groupSize.y, 1);
  }
}

namespace RootSignature {
namespace Resolve {
namespace Slot {
enum Enum {
  GBufferPosition = 0,     // t0
  GBufferNormalDepth,      // t1
  AOSurfaceAlbedo,         // t2
  MaterialID,              // t3
  ReservoirYIn,            // t4
  ReservoirWeightIn,       // t5
  LightSampleIn,           // t6
  LightNormalAreaIn,       // t7
  PrevReservoirYOut,       // u0
  PrevReservoirWeightOut,  // u1
  PrevLightSampleOut,      // u2
  PrevLightNormalAreaOut,  // u3
  RtColorOut,              // u4
  MaterialBuffer,          // t8
  ConstantBuffer,          // b0
  GlobalConstantBuffer,    // b1
  Count
};
}
}  // namespace Resolve
}  // namespace RootSignature

void Resolve::Initialize(ID3D12Device5* device, UINT frameCount,
                         UINT numCallsPerFrame) {
  // Create root signature.
  {
    using namespace RootSignature::Resolve;

    CD3DX12_DESCRIPTOR_RANGE ranges[Slot::Count];
    ranges[Slot::GBufferPosition].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                       0);  // t0
    ranges[Slot::GBufferNormalDepth].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                          1);  // t1
    ranges[Slot::AOSurfaceAlbedo].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                       2);                                 // t2
    ranges[Slot::MaterialID].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 3);  // t3
    ranges[Slot::ReservoirYIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                    4);  // t4
    ranges[Slot::ReservoirWeightIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                         5);  // t5
    ranges[Slot::LightSampleIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                     6);  // t6
    ranges[Slot::LightNormalAreaIn].Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1,
                                         7);  // t7
    ranges[Slot::PrevReservoirYOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                         0);  // u0
    ranges[Slot::PrevReservoirWeightOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV,
                                              1, 1);  // u1
    ranges[Slot::PrevLightSampleOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1,
                                          2);  // u2
    ranges[Slot::PrevLightNormalAreaOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV,
                                              1, 3);                       // u3
    ranges[Slot::RtColorOut].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 4);  // u4

    CD3DX12_ROOT_PARAMETER rootParameters[Slot::Count];
    for (int i = 0; i < Slot::Count - 3; ++i) {
      rootParameters[i].InitAsDescriptorTable(1, &ranges[i]);
    }

    rootParameters[Slot::MaterialBuffer].InitAsShaderResourceView(8);  // t8
    rootParameters[Slot::ConstantBuffer].InitAsConstantBufferView(0);  // b0
    rootParameters[Slot::GlobalConstantBuffer].InitAsConstantBufferView(
        1);  // b1

    CD3DX12_ROOT_SIGNATURE_DESC rootSignatureDesc(ARRAYSIZE(rootParameters),
                                                  rootParameters);
    SerializeAndCreateRootSignature(device, rootSignatureDesc, &m_rootSignature,
                                    L"Compute root signature: Resolve");
  }

  // Create compute pipeline state.
  {
    D3D12_COMPUTE_PIPELINE_STATE_DESC descComputePSO = {};
    descComputePSO.pRootSignature = m_rootSignature.Get();
    descComputePSO.CS = CD3DX12_SHADER_BYTECODE(
        static_cast<const void*>(g_pResolveCS), ARRAYSIZE(g_pResolveCS));
    ThrowIfFailed(device->CreateComputePipelineState(
        &descComputePSO, IID_PPV_ARGS(&m_pipelineStateObject)));
    m_pipelineStateObject->SetName(L"Pipeline state object: Resolve");
  }

  // Create shader resources
  {
    m_CB.Create(device, frameCount * numCallsPerFrame,
                L"Constant Buffer: Resolve");
  }
}

void Resolve::Run(ID3D12GraphicsCommandList4* commandList, UINT width,
                  UINT height, ID3D12DescriptorHeap* descriptorHeap,
                  D3D12_GPU_DESCRIPTOR_HANDLE gBufferPositionHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE gBufferNormalDepthHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE aoSurfaceAlbedoHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE materialIDInHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE reservoirYInHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE reservoirWeightInHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE lightSampleInHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaInHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE prevReservoirYOutHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE prevReservoirWeightOutHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE prevLightSampleOutHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE prevLightNormalAreaOutHandle,
                  D3D12_GPU_DESCRIPTOR_HANDLE rtColorOutHandle,
                  StructuredBuffer<PrimitiveMaterialBuffer>& materialBuffer,
                  ConstantBuffer<PathtracerConstantBuffer>& globalCB) {
  using namespace RootSignature::Resolve;
  using namespace DefaultComputeShaderParams;

  ScopedTimer _prof(L"Resolve", commandList);

  // Update the Constant Buffer.
  {
    m_CB->textureDim = XMUINT2(width, height);
    m_CB->invTextureDim = XMFLOAT2(1.f / width, 1.f / height);
    m_CBinstanceID = (m_CBinstanceID + 1) % m_CB.NumInstances();
    m_CB.CopyStagingToGpu(m_CBinstanceID);
  }

  // Set pipeline state and root signature.
  {
    commandList->SetDescriptorHeaps(1, &descriptorHeap);
    commandList->SetComputeRootSignature(m_rootSignature.Get());
    commandList->SetComputeRootDescriptorTable(Slot::GBufferPosition,
                                               gBufferPositionHandle);
    commandList->SetComputeRootDescriptorTable(Slot::GBufferNormalDepth,
                                               gBufferNormalDepthHandle);
    commandList->SetComputeRootDescriptorTable(Slot::AOSurfaceAlbedo,
                                               aoSurfaceAlbedoHandle);
    commandList->SetComputeRootDescriptorTable(Slot::MaterialID,
                                               materialIDInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirYIn,
                                               reservoirYInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::ReservoirWeightIn,
                                               reservoirWeightInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightSampleIn,
                                               lightSampleInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::LightNormalAreaIn,
                                               lightNormalAreaInHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevReservoirYOut,
                                               prevReservoirYOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevReservoirWeightOut,
                                               prevReservoirWeightOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevLightSampleOut,
                                               prevLightSampleOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::PrevLightNormalAreaOut,
                                               prevLightNormalAreaOutHandle);
    commandList->SetComputeRootDescriptorTable(Slot::RtColorOut,
                                               rtColorOutHandle);
    commandList->SetComputeRootConstantBufferView(
        Slot::ConstantBuffer, m_CB.GpuVirtualAddress(m_CBinstanceID));

    commandList->SetComputeRootShaderResourceView(
        Slot::MaterialBuffer, materialBuffer.GpuVirtualAddress());

    commandList->SetComputeRootConstantBufferView(
        Slot::GlobalConstantBuffer,
        globalCB.GpuVirtualAddress(globalCB->frameIndex));

    commandList->SetPipelineState(m_pipelineStateObject.Get());
  }

  // Dispatch compute shader.
  {
    XMUINT2 groupSize(CeilDivide(width, ThreadGroup::Width),
                      CeilDivide(height, ThreadGroup::Height));
    commandList->Dispatch(groupSize.x, groupSize.y, 1);
  }
}

}  // namespace Reuse