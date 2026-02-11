/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "MetalCommandBuffer.h"
#include "MetalContext.h"

namespace lvk {

MetalCommandBuffer::MetalCommandBuffer(MetalContext* ctx, id<MTLCommandBuffer> buffer) : ctx_(ctx), buffer_(buffer) {}

MetalCommandBuffer::~MetalCommandBuffer() {
  buffer_ = nil;
  renderEncoder_ = nil;
  computeEncoder_ = nil;
  blitEncoder_ = nil;
}

void MetalCommandBuffer::transitionToShaderReadOnly(TextureHandle surface) const {}

void MetalCommandBuffer::cmdPushDebugGroupLabel(const char* label, uint32_t colorRGBA) const {
  [buffer_ pushDebugGroup:[NSString stringWithUTF8String:label]];
  if (renderEncoder_) [renderEncoder_ pushDebugGroup:[NSString stringWithUTF8String:label]];
}

void MetalCommandBuffer::cmdInsertDebugEventLabel(const char* label, uint32_t colorRGBA) const {}

void MetalCommandBuffer::cmdPopDebugGroupLabel() const {
   if (renderEncoder_) [renderEncoder_ popDebugGroup];
   [buffer_ popDebugGroup];
}

void MetalCommandBuffer::cmdBindRayTracingPipeline(lvk::RayTracingPipelineHandle handle) {}

void MetalCommandBuffer::cmdBindComputePipeline(lvk::ComputePipelineHandle handle) {}
void MetalCommandBuffer::cmdDispatchThreadGroups(const Dimensions& threadgroupCount, const Dependencies& deps) {}

void MetalCommandBuffer::cmdBeginRendering(const lvk::RenderPass& renderPass, const lvk::Framebuffer& fb, const Dependencies& deps) {
  // printf("cmdBeginRendering\n");
  endEncoding();

  MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor renderPassDescriptor];
  
  // Color Attachments
  for (uint32_t i = 0; i < LVK_MAX_COLOR_ATTACHMENTS; i++) {
    if (renderPass.color[i].loadOp == LoadOp_Invalid) continue;
    
    TextureHandle texHandle = fb.color[i].texture;
    if (!texHandle.valid()) continue;

    // Get MTLTexture
    const MetalTexture* tex = ctx_->textures_.get(texHandle); 
    if (!tex || !tex->texture) continue;
    
    id<MTLTexture> mtlTex = tex->texture;
    
        if (mtlTex) {
            desc.colorAttachments[i].texture = mtlTex;
            desc.colorAttachments[i].slice = renderPass.color[i].layer;
            desc.colorAttachments[i].level = renderPass.color[i].level;
        
        switch (renderPass.color[i].loadOp) {
            case LoadOp_Load: desc.colorAttachments[i].loadAction = MTLLoadActionLoad; break;
            case LoadOp_Clear: 
                desc.colorAttachments[i].loadAction = MTLLoadActionClear;
                desc.colorAttachments[i].clearColor = MTLClearColorMake(
                    renderPass.color[i].clearColor.float32[0],
                    renderPass.color[i].clearColor.float32[1],
                    renderPass.color[i].clearColor.float32[2],
                    renderPass.color[i].clearColor.float32[3]);
                break;
            default: desc.colorAttachments[i].loadAction = MTLLoadActionDontCare; break;
        }
        
        switch (renderPass.color[i].storeOp) {
            case StoreOp_Store: desc.colorAttachments[i].storeAction = MTLStoreActionStore; break;
            case StoreOp_MsaaResolve: {
                desc.colorAttachments[i].storeAction = MTLStoreActionMultisampleResolve; 
                TextureHandle resolveHandle = fb.color[i].resolveTexture;
                if (resolveHandle.valid()) {
                     const MetalTexture* resolveTex = ctx_->textures_.get(resolveHandle);
                     if (resolveTex && resolveTex->texture) {
                         desc.colorAttachments[i].resolveTexture = resolveTex->texture;
                     }
                }
                break;
            }
            default: desc.colorAttachments[i].storeAction = MTLStoreActionDontCare; break;
        }
    }
  }

  // Depth/Stencil
  if (renderPass.depth.loadOp != LoadOp_Invalid) {
    TextureHandle texHandle = fb.depthStencil.texture;
    if (texHandle.valid()) {
      const MetalTexture* tex = ctx_->textures_.get(texHandle); 
      if (tex && tex->texture) {
          desc.depthAttachment.texture = tex->texture;
          desc.depthAttachment.clearDepth = renderPass.depth.clearDepth;
          switch (renderPass.depth.loadOp) {
              case LoadOp_Load: desc.depthAttachment.loadAction = MTLLoadActionLoad; break;
              case LoadOp_Clear: desc.depthAttachment.loadAction = MTLLoadActionClear; break;
              default: desc.depthAttachment.loadAction = MTLLoadActionDontCare; break;
          }
          switch (renderPass.depth.storeOp) {
              case StoreOp_Store: desc.depthAttachment.storeAction = MTLStoreActionStore; break;
              default: desc.depthAttachment.storeAction = MTLStoreActionDontCare; break;
          }
      }
    }
  }

  renderEncoder_ = [buffer_ renderCommandEncoderWithDescriptor:desc];
  if (renderEncoder_) {
      // Auto-set viewport/scissor based on first available attachment
      uint32_t width = 0, height = 0;
      id<MTLTexture> targetTex = nil;
      
      if (fb.color[0].texture.valid()) {
          targetTex = ctx_->textures_.get(fb.color[0].texture)->texture;
      } else if (fb.depthStencil.texture.valid()) {
          targetTex = ctx_->textures_.get(fb.depthStencil.texture)->texture;
      }
      
      if (targetTex) {
          width = (uint32_t)targetTex.width;
          height = (uint32_t)targetTex.height;
          MTLViewport vp = {0.0, 0.0, (double)width, (double)height, 0.0, 1.0};
          [renderEncoder_ setViewport:vp];
          MTLScissorRect sc = {0, 0, width, height};
          [renderEncoder_ setScissorRect:sc];
      }
  }
}

void MetalCommandBuffer::cmdEndRendering() {
  endEncoding();
}

void MetalCommandBuffer::cmdBindViewport(const Viewport& viewport) {
    if (!renderEncoder_) return;
    MTLViewport vp = {(double)viewport.x, (double)viewport.y, (double)viewport.width, (double)viewport.height, (double)viewport.minDepth, (double)viewport.maxDepth};
    [renderEncoder_ setViewport:vp];
}

void MetalCommandBuffer::cmdBindScissorRect(const ScissorRect& rect) {
    if (!renderEncoder_) return;
    MTLScissorRect sc = {rect.x, rect.y, rect.width, rect.height};
    [renderEncoder_ setScissorRect:sc];
}

void MetalCommandBuffer::cmdBindRenderPipeline(lvk::RenderPipelineHandle handle) {
  if (!renderEncoder_) return;

  const MetalRenderPipeline* pipeline = ctx_->renderPipelines_.get(handle);
  if (pipeline) {
     [renderEncoder_ setRenderPipelineState:pipeline->mps];
     if (pipeline->depthStencilState) {
        [renderEncoder_ setDepthStencilState:pipeline->depthStencilState];
     }
     [renderEncoder_ setCullMode:pipeline->cullMode];
     [renderEncoder_ setFrontFacingWinding:pipeline->winding];
     
     // Bind argument buffer for bindless textures at buffer(30)
     // Avoids conflict with cmdPushConstants which uses buffer(0)
     id<MTLBuffer> argBuffer = ctx_->getTextureArgumentBuffer();
     if (argBuffer) {
         [renderEncoder_ setFragmentBuffer:argBuffer offset:0 atIndex:30];
         // Make argument buffer resident (required since it is Untracked)
         [renderEncoder_ useResource:argBuffer usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
         // Make all 2D textures in argument buffer resident
         for (id<MTLTexture> tex : ctx_->getAllTextures2D()) {
             if (tex) {
                 [renderEncoder_ useResource:tex usage:MTLResourceUsageSample stages:MTLRenderStageFragment];
             }
         }
     }
     
     currentPrimitiveType_ = pipeline->primitiveType;
  }
}

static MTLCompareFunction compareOpToMetal(CompareOp op) {
  switch (op) {
    case CompareOp_Never: return MTLCompareFunctionNever;
    case CompareOp_Less: return MTLCompareFunctionLess;
    case CompareOp_Equal: return MTLCompareFunctionEqual;
    case CompareOp_LessEqual: return MTLCompareFunctionLessEqual;
    case CompareOp_Greater: return MTLCompareFunctionGreater;
    case CompareOp_NotEqual: return MTLCompareFunctionNotEqual;
    case CompareOp_GreaterEqual: return MTLCompareFunctionGreaterEqual;
    case CompareOp_AlwaysPass: return MTLCompareFunctionAlways;
    default: return MTLCompareFunctionAlways;
  }
}

void MetalCommandBuffer::cmdBindDepthState(const DepthState& state) {
    if (!renderEncoder_) return;
    
    MTLDepthStencilDescriptor* dsDesc = [[MTLDepthStencilDescriptor alloc] init];
    dsDesc.depthCompareFunction = compareOpToMetal(state.compareOp);
    dsDesc.depthWriteEnabled = state.isDepthWriteEnabled ? YES : NO;
    
    // @todo Cache these depth stencil states
    id<MTLDepthStencilState> ds = [ctx_->device_ newDepthStencilStateWithDescriptor:dsDesc];
    [renderEncoder_ setDepthStencilState:ds];
}

void MetalCommandBuffer::cmdBindVertexBuffer(uint32_t index, BufferHandle buffer, uint64_t bufferOffset) {
    if (!renderEncoder_) return;

    MetalBuffer* buf = ctx_->buffers_.get(buffer);
    if (buf && buf->buffer) {
        [renderEncoder_ setVertexBuffer:buf->buffer offset:bufferOffset atIndex:index];
    }
}


void MetalCommandBuffer::cmdBindBuffer(uint32_t index, BufferHandle buffer) {
    if (!renderEncoder_) return;
    MetalBuffer* buf = ctx_->buffers_.get(buffer);
    if (buf && buf->buffer) {
        [renderEncoder_ setVertexBuffer:buf->buffer offset:0 atIndex:index];
        [renderEncoder_ setFragmentBuffer:buf->buffer offset:0 atIndex:index];
    }
}

void MetalCommandBuffer::cmdBindIndexBuffer(BufferHandle indexBuffer, IndexFormat indexFormat, uint64_t indexBufferOffset) {
    MetalBuffer* buf = ctx_->buffers_.get(indexBuffer);
    if (buf && buf->buffer) {
        indexBuffer_ = buf->buffer;
        indexFormat_ = indexFormat;
        indexBufferOffset_ = indexBufferOffset;
    }
}

void lvk::MetalCommandBuffer::cmdBindTexture(uint32_t index, TextureHandle texture) {
    if (!renderEncoder_) return;
    MetalTexture* tex = ctx_->textures_.get(texture);
    if (tex && tex->texture) {
        [renderEncoder_ setVertexTexture:tex->texture atIndex:index];
        [renderEncoder_ setFragmentTexture:tex->texture atIndex:index];
    }
}

void MetalCommandBuffer::cmdPushConstants(const void* data, size_t size, size_t offset) {
    if (!renderEncoder_) return;
    
    // Bind as bytes to buffer 29 (Avoid Vertex Buffer 0-3 and Texture Buffer 30)
    [renderEncoder_ setVertexBytes:data length:size atIndex:29];
    [renderEncoder_ setFragmentBytes:data length:size atIndex:29];
    
    // Hijack ImGui Texture Binding
    // ImGui bind data size is 32 bytes (4 floats + u64 + u32 + u32)
    if (size == 32) {
        struct ImGuiPC {
            float LRTB[4];
            uint64_t vb;
            uint32_t textureId;
            uint32_t samplerId;
        };
        const ImGuiPC* pc = (const ImGuiPC*)data;
        
        MetalTexture* tex = ctx_->textures_.get(ctx_->textures_.getHandle(pc->textureId));
        if (tex && tex->texture) {
            [renderEncoder_ setFragmentTexture:tex->texture atIndex:0];
        }
        
        MetalSampler* smp = ctx_->samplers_.get(ctx_->samplers_.getHandle(pc->samplerId));
        if (smp && smp->sampler) {
            [renderEncoder_ setFragmentSamplerState:smp->sampler atIndex:0];
        }
    }
    
    // Hijack 002_RenderToCubeMap Bindings
    // struct { mat4 mvp; uint32_t texture; } = 64 + 4 = 68 bytes
    if (size == 68) {
        struct CubeMapPC {
            float mvp[16];
            uint32_t textureId;
        };
        const CubeMapPC* pc = (const CubeMapPC*)data;
        
        MetalTexture* tex = ctx_->textures_.get(ctx_->textures_.getHandle(pc->textureId));
        if (tex && tex->texture) {
            [renderEncoder_ setFragmentTexture:tex->texture atIndex:0];
        }
        
        // Use a default linear sampler for the cubemap
        MTLSamplerDescriptor* sDesc = [[MTLSamplerDescriptor alloc] init];
        sDesc.minFilter = MTLSamplerMinMagFilterLinear;
        sDesc.magFilter = MTLSamplerMinMagFilterLinear;
        sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        sDesc.rAddressMode = MTLSamplerAddressModeClampToEdge;
        id<MTLSamplerState> sampler = [ctx_->getMTLDevice() newSamplerStateWithDescriptor:sDesc];
        [renderEncoder_ setFragmentSamplerState:sampler atIndex:0];
    }
}

void MetalCommandBuffer::cmdCopyBuffer(BufferHandle srcBuffer, BufferHandle dstBuffer, size_t srcOffset, size_t dstOffset, size_t size) {
    MetalBuffer* src = ctx_->buffers_.get(srcBuffer);
    MetalBuffer* dst = ctx_->buffers_.get(dstBuffer);
    if (!src || !src->buffer || !dst || !dst->buffer) return;

    endEncoding();
    id<MTLBlitCommandEncoder> blit = [buffer_ blitCommandEncoder];
    [blit copyFromBuffer:src->buffer sourceOffset:srcOffset toBuffer:dst->buffer destinationOffset:dstOffset size:size];
    [blit endEncoding];
}
void MetalCommandBuffer::cmdFillBuffer(BufferHandle buffer, size_t bufferOffset, size_t size, uint32_t data) {}
void MetalCommandBuffer::cmdUpdateBuffer(BufferHandle handle, size_t offset, size_t size, const void* data) {
    MetalBuffer* buf = ctx_->buffers_.get(handle);
    if (buf && buf->buffer) {
        if (buf->buffer.storageMode == MTLStorageModePrivate) {
            id<MTLBuffer> staging = [ctx_->device_ newBufferWithBytes:data length:size options:MTLResourceStorageModeShared];
            endEncoding();
            id<MTLBlitCommandEncoder> blit = [buffer_ blitCommandEncoder];
            [blit copyFromBuffer:staging sourceOffset:0 toBuffer:buf->buffer destinationOffset:offset size:size];
            [blit endEncoding];
        } else {
            memcpy((uint8_t*)buf->buffer.contents + offset, data, size);
            [buf->buffer didModifyRange:NSMakeRange(offset, size)];
        }
    }
}

void MetalCommandBuffer::cmdDraw(uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t baseInstance) {
   if (!renderEncoder_) return;
   
   [renderEncoder_ drawPrimitives:currentPrimitiveType_ vertexStart:firstVertex vertexCount:vertexCount instanceCount:instanceCount baseInstance:baseInstance];
}

void MetalCommandBuffer::cmdDrawIndexed(uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t vertexOffset, uint32_t baseInstance) {
    if (!renderEncoder_) return;
    if (!indexBuffer_) {
        printf("cmdDrawIndexed: No index buffer bound!\n");
        return;
    }
    
    MTLIndexType idxType = (indexFormat_ == IndexFormat_UI16) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
    size_t idxSize = (indexFormat_ == IndexFormat_UI16) ? 2 : 4;

    [renderEncoder_ drawIndexedPrimitives:currentPrimitiveType_ 
                               indexCount:indexCount 
                                indexType:idxType 
                              indexBuffer:indexBuffer_ 
                        indexBufferOffset:indexBufferOffset_ + (firstIndex * idxSize)
                            instanceCount:instanceCount 
                               baseVertex:vertexOffset 
                             baseInstance:baseInstance];
}
void MetalCommandBuffer::cmdDrawIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride) {}
void MetalCommandBuffer::cmdDrawIndexedIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride) {}
void MetalCommandBuffer::cmdDrawIndexedIndirectCount(BufferHandle indirectBuffer, size_t indirectBufferOffset, BufferHandle countBuffer, size_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride) {}
void MetalCommandBuffer::cmdDrawMeshTasks(const Dimensions& threadgroupCount) {}
void MetalCommandBuffer::cmdDrawMeshTasksIndirect(BufferHandle indirectBuffer, size_t indirectBufferOffset, uint32_t drawCount, uint32_t stride) {}
void MetalCommandBuffer::cmdDrawMeshTasksIndirectCount(BufferHandle indirectBuffer, size_t indirectBufferOffset, BufferHandle countBuffer, size_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride) {}
void MetalCommandBuffer::cmdTraceRays(uint32_t width, uint32_t height, uint32_t depth, const Dependencies& deps) {}

void MetalCommandBuffer::cmdSetBlendColor(const float color[4]) {}
void MetalCommandBuffer::cmdSetDepthBias(float constantFactor, float slopeFactor, float clamp) {
    depthBiasConstant_ = constantFactor;
    depthBiasSlopeScale_ = slopeFactor;
    depthBiasClamp_ = clamp;
    if (renderEncoder_ && depthBiasEnabled_) {
        [renderEncoder_ setDepthBias:constantFactor slopeScale:slopeFactor clamp:clamp];
    }
}

void MetalCommandBuffer::cmdSetDepthBiasEnable(bool enable) {
    depthBiasEnabled_ = enable;
    if (renderEncoder_) {
        if (enable) {
            [renderEncoder_ setDepthBias:depthBiasConstant_ slopeScale:depthBiasSlopeScale_ clamp:depthBiasClamp_];
        } else {
            [renderEncoder_ setDepthBias:0.0f slopeScale:0.0f clamp:0.0f];
        }
    }
}

void MetalCommandBuffer::cmdResetQueryPool(QueryPoolHandle pool, uint32_t firstQuery, uint32_t queryCount) {}
void MetalCommandBuffer::cmdWriteTimestamp(QueryPoolHandle pool, uint32_t query) {}

void MetalCommandBuffer::cmdClearColorImage(TextureHandle tex, const ClearColorValue& value, const TextureLayers& layers) {}
void MetalCommandBuffer::cmdCopyImage(TextureHandle src, TextureHandle dst, const Dimensions& extent, const Offset3D& srcOffset, const Offset3D& dstOffset, const TextureLayers& srcLayers, const TextureLayers& dstLayers) {}
void MetalCommandBuffer::cmdGenerateMipmap(TextureHandle handle) {
    MetalTexture* tex = ctx_->textures_.get(handle);
    if (!tex || !tex->texture) return;
    if (tex->texture.mipmapLevelCount <= 1) return;

    endEncoding();
    id<MTLBlitCommandEncoder> blit = [buffer_ blitCommandEncoder];
    [blit generateMipmapsForTexture:tex->texture];
    [blit endEncoding];
}
void MetalCommandBuffer::cmdUpdateTLAS(AccelStructHandle handle, BufferHandle instancesBuffer) {}

void MetalCommandBuffer::commit() {
    endEncoding();
    [buffer_ commit];
}

void MetalCommandBuffer::endEncoding() {
  if (renderEncoder_) {
    [renderEncoder_ endEncoding];
    renderEncoder_ = nil;
  }
  if (computeEncoder_) {
    [computeEncoder_ endEncoding];
    computeEncoder_ = nil;
  }
  if (blitEncoder_) {
    [blitEncoder_ endEncoding];
    blitEncoder_ = nil;
  }
}

} // namespace lvk
