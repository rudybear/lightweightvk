/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <lvk/LVK.h>
#include <lvk/Pool.h>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

namespace lvk {

struct MetalShaderModule {
  id<MTLLibrary> library = nil;
  std::string entryPointName = "main0";  // Default to main0
  std::string source;
};

struct MetalRenderPipeline {
  id<MTLRenderPipelineState> mps;
  MTLPrimitiveType primitiveType = MTLPrimitiveTypeTriangle;
  id<MTLDepthStencilState> depthStencilState = nil;
  MTLCullMode cullMode = MTLCullModeNone;
  MTLWinding winding = MTLWindingCounterClockwise;
  float depthBias = 0.0f;
  float depthSlopeScale = 0.0f;
  float depthClamp = 0.0f;
};

struct MetalTexture {
  id<MTLTexture> texture = nil;
  uint32_t width = 0;
  uint32_t height = 0;
};

struct MetalBuffer {
  id<MTLBuffer> buffer = nil;
};

struct MetalSampler {
  id<MTLSamplerState> sampler = nil;
};

class MetalContext : public IContext {
 public:
  friend class MetalCommandBuffer;
  MetalContext(void* window, uint32_t width, uint32_t height, const ContextConfig& config);
  ~MetalContext() override;

  ICommandBuffer& acquireCommandBuffer() override;
  SubmitHandle submit(ICommandBuffer& commandBuffer, TextureHandle present = {}) override;
  void wait(SubmitHandle handle) override;

  Holder<BufferHandle> createBuffer(const BufferDesc& desc, const char* debugName = nullptr, Result* outResult = nullptr) override;
  Holder<SamplerHandle> createSampler(const SamplerStateDesc& desc, Result* outResult = nullptr) override;
  Holder<TextureHandle> createTexture(const TextureDesc& desc, const char* debugName = nullptr, Result* outResult = nullptr) override;
  Holder<TextureHandle> createTextureView(TextureHandle texture, const TextureViewDesc& desc, const char* debugName = nullptr, Result* outResult = nullptr) override;
  Holder<ComputePipelineHandle> createComputePipeline(const ComputePipelineDesc& desc, Result* outResult = nullptr) override;
  Holder<RenderPipelineHandle> createRenderPipeline(const RenderPipelineDesc& desc, Result* outResult = nullptr) override;
  Holder<RayTracingPipelineHandle> createRayTracingPipeline(const RayTracingPipelineDesc& desc, Result* outResult = nullptr) override;
  Holder<ShaderModuleHandle> createShaderModule(const ShaderModuleDesc& desc, Result* outResult = nullptr) override;
  Holder<QueryPoolHandle> createQueryPool(uint32_t numQueries, const char* debugName, Result* outResult = nullptr) override;
  Holder<AccelStructHandle> createAccelerationStructure(const AccelStructDesc& desc, Result* outResult = nullptr) override;

  void destroy(ComputePipelineHandle handle) override;
  void destroy(RenderPipelineHandle handle) override;
  void destroy(RayTracingPipelineHandle handle) override;
  void destroy(ShaderModuleHandle handle) override;
  void destroy(SamplerHandle handle) override;
  void destroy(BufferHandle handle) override;
  void destroy(TextureHandle handle) override;
  void destroy(QueryPoolHandle handle) override;
  void destroy(AccelStructHandle handle) override;
  void destroy(Framebuffer& fb) override;

  uint64_t gpuAddress(AccelStructHandle handle) const override;

  AccelStructSizes getAccelStructSizes(const AccelStructDesc& desc, Result* outResult = nullptr) const override;

  Result upload(BufferHandle handle, const void* data, size_t size, size_t offset = 0) override;
  Result download(BufferHandle handle, void* data, size_t size, size_t offset) override;
  uint8_t* getMappedPtr(BufferHandle handle) const override;
  uint64_t gpuAddress(BufferHandle handle, size_t offset = 0) const override;
  void flushMappedMemory(BufferHandle handle, size_t offset, size_t size) const override;
  uint32_t getMaxStorageBufferRange() const override;

  Result upload(TextureHandle handle, const TextureRangeDesc& range, const void* data, uint32_t bufferRowLength = 0) override;
  Result download(TextureHandle handle, const TextureRangeDesc& range, void* outData) override;
  Dimensions getDimensions(TextureHandle handle) const override;
  float getAspectRatio(TextureHandle handle) const override;
  Format getFormat(TextureHandle handle) const override;

  TextureHandle getCurrentSwapchainTexture() override;
  Format getSwapchainFormat() const override;
  ColorSpace getSwapchainColorSpace() const override;
  uint32_t getSwapchainCurrentImageIndex() const override;
  uint32_t getNumSwapchainImages() const override;
  void recreateSwapchain(int newWidth, int newHeight) override;

  uint32_t getFramebufferMSAABitMask() const override;

  double getTimestampPeriodToMs() const override;
  bool getQueryPoolResults(QueryPoolHandle pool, uint32_t firstQuery, uint32_t queryCount, size_t dataSize, void* outData, size_t stride) const override;

  // Metal-specific: Create argument buffer for bindless textures
  void createTextureArgumentBuffer(const std::vector<TextureHandle>& textures) override;
  id<MTLBuffer> getTextureArgumentBuffer() const { return bindlessBuffer_; }
  
  // Vulkan-equivalent bindless resource table
  void updateBindlessTexture(uint32_t index, id<MTLTexture> texture, bool isCube = false, bool isShadow = false);
  void updateBindlessSampler(uint32_t index, id<MTLSamplerState> sampler, bool isShadow = false);
  id<MTLBuffer> getBindlessBuffer() const { return bindlessBuffer_; }
  const std::vector<id<MTLTexture>>& getAllTextures2D() const { return textures2D_; }
  const std::vector<id<MTLTexture>>& getAllTexturesCube() const { return texturesCube_; }
  const std::vector<id<MTLTexture>>& getAllTexturesShadow() const { return texturesShadow_; }

  id<MTLDevice> getMTLDevice() const { return device_; }

 private:
  id<MTLDevice> device_ = nil;
  id<MTLCommandQueue> commandQueue_ = nil;
  Pool<ShaderModule, MetalShaderModule> shaderModules_;
  Pool<RenderPipeline, MetalRenderPipeline> renderPipelines_;
  Pool<Texture, MetalTexture> textures_;
  Pool<Buffer, MetalBuffer> buffers_;
  Pool<Sampler, MetalSampler> samplers_;
  CAMetalLayer* swapchainLayer_ = nil;
  id<CAMetalDrawable> currentDrawable_ = nil;
  TextureHandle swapchainHandle_;
  
  // Bindless resource table (Vulkan-equivalent)
  static constexpr uint32_t kMaxTextures2D = 4096;
  static constexpr uint32_t kMaxTexturesCube = 256;
  static constexpr uint32_t kMaxTexturesShadow = 64;
  static constexpr uint32_t kMaxSamplers = 64;
  
  id<MTLBuffer> bindlessBuffer_ = nil;           // GPU buffer holding resource IDs
  std::vector<id<MTLTexture>> textures2D_;       // All 2D textures
  std::vector<id<MTLTexture>> texturesCube_;     // All cubemap textures
  std::vector<id<MTLTexture>> texturesShadow_;   // All shadow map textures
  std::vector<id<MTLSamplerState>> bindlessSamplers_;    // All samplers for bindless access
  std::vector<id<MTLSamplerState>> samplersShadow_; // Shadow comparison samplers
  
  // Legacy argument buffer support (for compatibility)
  id<MTLArgumentEncoder> textureArgumentEncoder_ = nil;
  id<MTLBuffer> textureArgumentBuffer_ = nil;
  std::vector<id<MTLTexture>> boundTextures_;
  
  // Basic implementation of command buffer recycling
  std::unique_ptr<class MetalCommandBuffer> currentCommandBuffer_;
};

} // namespace lvk
