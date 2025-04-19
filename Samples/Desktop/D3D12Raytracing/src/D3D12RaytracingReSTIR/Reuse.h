#pragma once

namespace Reuse {

class SpatialReuse {
 public:
  void Initialize(ID3D12Device5* device, UINT frameCount,
                  UINT numCallsPerFrame = 1);
  void Run(
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
      D3D12_GPU_DESCRIPTOR_HANDLE
          outputPartialDistanceDerivativesResourceHandle,
      D3D12_GPU_DESCRIPTOR_HANDLE outputMotionVectorResourceHandle,
      D3D12_GPU_DESCRIPTOR_HANDLE outputPrevFrameHitPositionResourceHandle,
      D3D12_GPU_DESCRIPTOR_HANDLE outputDepthResourceHandle,
      D3D12_GPU_DESCRIPTOR_HANDLE outputSurfaceAlbedoResourceHandle);

 private:
  ComPtr<ID3D12RootSignature> m_rootSignature;
  ComPtr<ID3D12PipelineState> m_pipelineStateObject;
  ConstantBuffer<TextureDimConstantBuffer> m_CB;
  UINT m_CBinstanceID = 0;
};

class TemporalReuse {
 public:
  enum FilterType {
    Filter2x2FloatR = 0,
    Filter2x2UintR,
    Filter2x2FloatRG,
    Count
  };

  void Initialize(ID3D12Device5* device, UINT frameCount,
                  UINT numCallsPerFrame = 1);
  void Run(ID3D12GraphicsCommandList4* commandList, UINT width, UINT height,
           FilterType type, ID3D12DescriptorHeap* descriptorHeap,
           D3D12_GPU_DESCRIPTOR_HANDLE inputResourceHandle,
           D3D12_GPU_DESCRIPTOR_HANDLE inputLowResNormalResourceHandle,
           D3D12_GPU_DESCRIPTOR_HANDLE inputHiResNormalResourceHandle,
           D3D12_GPU_DESCRIPTOR_HANDLE
               inputHiResPartialDistanceDerivativeResourceHandle,
           D3D12_GPU_DESCRIPTOR_HANDLE outputResourceHandle);

 private:
  ComPtr<ID3D12RootSignature> m_rootSignature;
  ComPtr<ID3D12PipelineState> m_pipelineStateObjects[FilterType::Count];
  ConstantBuffer<DownAndUpsampleFilterConstantBuffer> m_CB;
  UINT m_CBinstanceID = 0;
};

}  // namespace GpuKernels
