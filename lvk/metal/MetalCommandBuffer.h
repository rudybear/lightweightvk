/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <lvk/LVK.h>
#import <Metal/Metal.h>

namespace lvk {

class MetalContext;

class MetalCommandBuffer : public ICommandBuffer {
 public:
  MetalCommandBuffer(MetalContext* ctx, id<MTLCommandBuffer> buffer);
  ~MetalCommandBuffer() override;

  void transitionToShaderReadOnly(TextureHandle surface) const override;

  void cmdPushDebugGroupLabel(const char* label, uint32_t colorRGBA = 0xffffffff) const override;
  void cmdInsertDebugEventLabel(const char* label, uint32_t colorRGBA = 0xffffffff) const override;
  void cmdPopDebugGroupLabel() const override;

  void cmdBindRayTracingPipeline(lvk::RayTracingPipelineHandle handle) override;

  void cmdBindComputePipeline(lvk::ComputePipelineHandle handle) override;
  void cmdDispatchThreadGroups(const Dimensions& threadgroupCount, const Dependencies& deps = {}) override;

  void cmdBeginRendering(const lvk::RenderPass& renderPass, const lvk::Framebuffer& desc, const Dependencies& deps = {}) override;
  void cmdEndRendering() override;

  void cmdBindViewport(const Viewport& viewport) override;
  void cmdBindScissorRect(const ScissorRect& rect) override;

  void cmdBindRenderPipeline(lvk::RenderPipelineHandle handle) override;
  void cmdBindDepthState(const DepthState& state) override;

  void cmdBindVertexBuffer(uint32_t index, BufferHandle buffer, uint64_t bufferOffset = 0) override;
  void cmdBindIndexBuffer(BufferHandle indexBuffer, IndexFormat indexFormat, uint64_t indexBufferOffset = 0) override;
  void cmdBindBuffer(uint32_t index, BufferHandle buffer) override;
  void cmdBindTexture(uint32_t index, TextureHandle texture) override;
  void cmdPushConstants(const void* data, size_t size, size_t offset = 0) override;

  void cmdCopyBuffer(BufferHandle srcBuffer, BufferHandle dstBuffer, size_t srcOffset, size_t dstOffset, size_t size) override;
  void cmdFillBuffer(BufferHandle buffer, size_t bufferOffset, size_t size, uint32_t data) override;
  void cmdUpdateBuffer(BufferHandle buffer, size_t bufferOffset, size_t size, const void* data) override;

  void cmdDraw(uint32_t vertexCount, uint32_t instanceCount = 1, uint32_t firstVertex = 0, uint32_t baseInstance = 0) override;
  void cmdDrawIndexed(uint32_t indexCount, uint32_t instanceCount = 1, uint32_t firstIndex = 0, int32_t vertexOffset = 0, uint32_t baseInstance = 0) override;
  void cmdDrawIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride = 0) override;
  void cmdDrawIndexedIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride = 0) override;
  void cmdDrawIndexedIndirectCount(BufferHandle indirectBuffer, size_t indirectBufferOffset, BufferHandle countBuffer, size_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride = 0) override;
  void cmdDrawMeshTasks(const Dimensions& threadgroupCount) override;
  void cmdDrawMeshTasksIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride = 0) override;
  void cmdDrawMeshTasksIndirectCount(BufferHandle indirectBuffer, size_t indirectBufferOffset, BufferHandle countBuffer, size_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride = 0) override;
  void cmdTraceRays(uint32_t width, uint32_t height, uint32_t depth = 1, const Dependencies& deps = {}) override;

  void cmdSetBlendColor(const float color[4]) override;
  void cmdSetDepthBias(float constantFactor, float slopeFactor, float clamp = 0.0f) override;
  void cmdSetDepthBiasEnable(bool enable) override;

  void cmdResetQueryPool(QueryPoolHandle pool, uint32_t firstQuery, uint32_t queryCount) override;
  void cmdWriteTimestamp(QueryPoolHandle pool, uint32_t query) override;

  void cmdClearColorImage(TextureHandle tex, const ClearColorValue& value, const TextureLayers& layers = {}) override;
  void cmdCopyImage(TextureHandle src, TextureHandle dst, const Dimensions& extent, const Offset3D& srcOffset = {}, const Offset3D& dstOffset = {}, const TextureLayers& srcLayers = {}, const TextureLayers& dstLayers = {}) override;
  void cmdGenerateMipmap(TextureHandle handle) override;
  void cmdUpdateTLAS(AccelStructHandle handle, BufferHandle instancesBuffer) override;

  id<MTLCommandBuffer> getMTLCommandBuffer() const { return buffer_; }
  void commit();

 private:
  MetalContext* ctx_ = nullptr;
  id<MTLCommandBuffer> buffer_ = nil;
  id<MTLRenderCommandEncoder> renderEncoder_ = nil;
  id<MTLComputeCommandEncoder> computeEncoder_ = nil;
  id<MTLBlitCommandEncoder> blitEncoder_ = nil;
  MTLPrimitiveType currentPrimitiveType_ = MTLPrimitiveTypeTriangle;
  
  id<MTLBuffer> indexBuffer_ = nil;
  NSUInteger indexBufferOffset_ = 0;
  lvk::IndexFormat indexFormat_ = lvk::IndexFormat_UI16;

  bool depthBiasEnabled_ = false;
  float depthBiasConstant_ = 0.0f;
  float depthBiasSlopeScale_ = 0.0f;
  float depthBiasClamp_ = 0.0f;

  void endEncoding();
};

} // namespace lvk
