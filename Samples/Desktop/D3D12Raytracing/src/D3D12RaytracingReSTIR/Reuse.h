#pragma once

namespace Reuse {
class SpatialReuse {
 public:
  void Initialize(ID3D12Device5* device, UINT frameCount,
                  UINT numCallsPerFrame = 1);
  void Run(ID3D12GraphicsCommandList4* commandList,
           ID3D12DescriptorHeap* descriptorHeap, UINT width, UINT height,
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
           D3D12_GPU_DESCRIPTOR_HANDLE lightNormalAreaOutHandle);

 private:
  ComPtr<ID3D12RootSignature> m_rootSignature;
  ComPtr<ID3D12PipelineState> m_pipelineStateObject;
  ConstantBuffer<TextureDimConstantBuffer> m_CB;
  UINT m_CBinstanceID = 0;
};

class TemporalReuse {
 public:
  void Initialize(ID3D12Device5* device, UINT frameCount,
                  UINT numCallsPerFrame = 1);
  void Run(ID3D12GraphicsCommandList4* commandList, UINT width, UINT height,
           ID3D12DescriptorHeap* descriptorHeap,
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
           ConstantBuffer<PathtracerConstantBuffer>& globalCB);

 private:
  ComPtr<ID3D12RootSignature> m_rootSignature;
  ComPtr<ID3D12PipelineState> m_pipelineStateObject;
  ConstantBuffer<TextureDimConstantBuffer> m_CB;
  UINT m_CBinstanceID = 0;
};

class Resolve {
 public:
  void Initialize(ID3D12Device5* device, UINT frameCount,
                  UINT numCallsPerFrame = 1);
  void Run(ID3D12GraphicsCommandList4* commandList, UINT width, UINT height,
           ID3D12DescriptorHeap* descriptorHeap,
           D3D12_GPU_DESCRIPTOR_HANDLE gBufferPositionHandle,
           D3D12_GPU_DESCRIPTOR_HANDLE gBufferNormalDepthHandle,
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
           ConstantBuffer<PathtracerConstantBuffer>& globalCB);

 private:
  ComPtr<ID3D12RootSignature> m_rootSignature;
  ComPtr<ID3D12PipelineState> m_pipelineStateObject;
  ConstantBuffer<TextureDimConstantBuffer> m_CB;
  UINT m_CBinstanceID = 0;
};

}  // namespace Reuse
