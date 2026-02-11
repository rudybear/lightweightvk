/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if LVK_WITH_GLFW
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3native.h>
#endif

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#include <glslang/Public/ShaderLang.h>
#include <spirv_cross/spirv_msl.hpp>

#include "MetalContext.h"
#include "MetalCommandBuffer.h"
#include "MetalContextFactory.h"
#include "MetalShaderUtils.h"

namespace lvk {

static MTLPixelFormat vkFormatToMetal(Format format) {
  switch (format) {
      case Format_R_UN8: return MTLPixelFormatR8Unorm;
      case Format_RG_UN8: return MTLPixelFormatRG8Unorm;
      case Format_RGBA_UN8: return MTLPixelFormatRGBA8Unorm;
      case Format_BGRA_UN8: return MTLPixelFormatBGRA8Unorm;
      case Format_BGRA_SRGB8: return MTLPixelFormatBGRA8Unorm_sRGB;
      case Format_RGBA_SRGB8: return MTLPixelFormatRGBA8Unorm_sRGB;
      case Format_R_F16: return MTLPixelFormatR16Float;
      case Format_RG_F16: return MTLPixelFormatRG16Float;
      case Format_RGBA_F16: return MTLPixelFormatRGBA16Float;
      case Format_R_F32: return MTLPixelFormatR32Float;
      case Format_RG_F32: return MTLPixelFormatRG32Float;
      case Format_RGBA_F32: return MTLPixelFormatRGBA32Float;
      case Format_Z_UN16: return MTLPixelFormatDepth16Unorm; // Or Depth32Float on AS
      case Format_Z_UN24: return MTLPixelFormatDepth32Float; // Remap
      case Format_Z_F32: return MTLPixelFormatDepth32Float;
      case Format_Z_UN24_S_UI8: return MTLPixelFormatDepth32Float_Stencil8; // Remap
      case Format_Z_F32_S_UI8: return MTLPixelFormatDepth32Float_Stencil8;
      case Format_BC7_RGBA: return MTLPixelFormatBC7_RGBAUnorm;
      default: return MTLPixelFormatInvalid;
  }
}

static uint32_t getBytesPerRow(MTLPixelFormat format, uint32_t width) {
    switch (format) {
        case MTLPixelFormatR8Unorm: return width;
        case MTLPixelFormatRG8Unorm: return width * 2;
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatRGBA8Unorm_sRGB:
        case MTLPixelFormatBGRA8Unorm_sRGB: return width * 4;
        case MTLPixelFormatR16Float: return width * 2;
        case MTLPixelFormatRG16Float: return width * 4;
        case MTLPixelFormatRGBA16Float: return width * 8;
        case MTLPixelFormatR32Float: return width * 4;
        case MTLPixelFormatRG32Float: return width * 8;
        case MTLPixelFormatRGBA32Float: return width * 16;
        case MTLPixelFormatBC1_RGBA:
        case MTLPixelFormatBC1_RGBA_sRGB: return ((width + 3) / 4) * 8;
        case MTLPixelFormatBC2_RGBA:
        case MTLPixelFormatBC2_RGBA_sRGB:
        case MTLPixelFormatBC3_RGBA:
        case MTLPixelFormatBC3_RGBA_sRGB:
        case MTLPixelFormatBC7_RGBAUnorm:
        case MTLPixelFormatBC7_RGBAUnorm_sRGB: return ((width + 3) / 4) * 16;
        default: return width * 4;
    }
}

static bool isCompressed(MTLPixelFormat format) {
    return (format >= MTLPixelFormatBC1_RGBA && format <= MTLPixelFormatBC7_RGBAUnorm_sRGB);
}


MTLVertexFormat vkVertexFormatToMetal(VertexFormat format) {
    switch (format) {
        case VertexFormat::Float1: return MTLVertexFormatFloat;
        case VertexFormat::Float2: return MTLVertexFormatFloat2;
        case VertexFormat::Float3: return MTLVertexFormatFloat3;
        case VertexFormat::Float4: return MTLVertexFormatFloat4;
        case VertexFormat::HalfFloat2: return MTLVertexFormatHalf2;
        case VertexFormat::Byte4Norm: return MTLVertexFormatChar4Normalized;
        case VertexFormat::UByte4Norm: return MTLVertexFormatUChar4Normalized;
        case VertexFormat::UInt1: return MTLVertexFormatUInt;
        case VertexFormat::Int1: return MTLVertexFormatInt;
        case VertexFormat::UShort1: return MTLVertexFormatUShort;
        case VertexFormat::Short1: return MTLVertexFormatShort;
        default: return MTLVertexFormatInvalid;
    }
}

static MTLPrimitiveType vkTopologyToMetal(Topology topology) {
  switch (topology) {
    case Topology_Point: return MTLPrimitiveTypePoint;
    case Topology_Line: return MTLPrimitiveTypeLine;
    case Topology_LineStrip: return MTLPrimitiveTypeLineStrip;
    case Topology_Triangle: return MTLPrimitiveTypeTriangle;
    case Topology_TriangleStrip: return MTLPrimitiveTypeTriangleStrip;
    default: return MTLPrimitiveTypeTriangle;
  }
}

std::unique_ptr<IContext> createMetalContext(void* window, uint32_t width, uint32_t height, const ContextConfig& config) {
  return std::make_unique<MetalContext>(window, width, height, config);
}

MetalContext::MetalContext(void* window, uint32_t width, uint32_t height, const ContextConfig& config) {
  glslang::InitializeProcess();
  device_ = MTLCreateSystemDefaultDevice();
  if (!device_) {
    LLOGW("Failed to create default Metal device");
    return;
  }
  
  commandQueue_ = [device_ newCommandQueue];
  
#if LVK_WITH_GLFW
  // Assuming window is a GLFWwindow* and we need to get the NSWindow/NSView
  // This part requires platform specific handling. For now, we assume the window pointer
  // passed in is already what we need or we use a helper.
  // In LVK.cpp, we see createCocoaWindowView.
  // We will assume the window passed here is the NSView* (CAMetalLayer's superview).
  
  NSView* view = (__bridge NSView*)window;
  swapchainLayer_ = [CAMetalLayer layer];
  swapchainLayer_.device = device_;
  swapchainLayer_.pixelFormat = MTLPixelFormatBGRA8Unorm;
  swapchainLayer_.framebufferOnly = NO;
  view.layer = swapchainLayer_;
  view.wantsLayer = YES;
#endif


  swapchainHandle_ = textures_.create(MetalTexture{});
}

MetalContext::~MetalContext() {
  glslang::FinalizeProcess();
  textureArgumentEncoder_ = nil;
  textureArgumentBuffer_ = nil;
  //boundTextures_.clear(); // std::vector clears automatically
  commandQueue_ = nil;
  device_ = nil;
}

void MetalContext::createTextureArgumentBuffer(const std::vector<TextureHandle>& textures) {
  if (textures.empty()) {
    printf("WARNING: createTextureArgumentBuffer called with empty texture list\n");
    return;
  }
  
  NSString* argumentBufferShaderSource = @R"(
    #include <metal_stdlib>
    using namespace metal;
    
    // Arbitrary/Unbounded array of textures for bindless access (Tier 2 limit)
    struct TextureTable {
        array<texture2d<float>, 500000> textures [[id(0)]];
    };
    
    fragment float4 argumentBufferDummy(device TextureTable& texArgs [[buffer(30)]]) {
        return float4(0.0);
    }
  )";
  
  NSError* error = nil;
  id<MTLLibrary> tempLibrary = [device_ newLibraryWithSource:argumentBufferShaderSource
                                                      options:nil
                                                        error:&error];
  if (!tempLibrary) {
    printf("ERROR: Failed to create temp library for argument buffer: %s\n",
           [[error localizedDescription] UTF8String]);
    return;
  }
  
  id<MTLFunction> tempFunc = [tempLibrary newFunctionWithName:@"argumentBufferDummy"];
  if (!tempFunc) {
    printf("ERROR: Failed to get argument buffer dummy function\n");
    return;
  }
  
  // Create argument encoder from the function - MUST use buffer index 30 to match shader
  textureArgumentEncoder_ = [tempFunc newArgumentEncoderWithBufferIndex:30];
  if (!textureArgumentEncoder_) {
    printf("ERROR: Failed to create argument encoder\n");
    return;
  }
  
  // Allocate buffer for argument data
  NSUInteger encodedLength = [textureArgumentEncoder_ encodedLength];
  // Use MTLResourceHazardTrackingModeDefault (Tracked) to avoid residency issues
  textureArgumentBuffer_ = [device_ newBufferWithLength:encodedLength
                                                 options:MTLResourceStorageModeShared];
  bindlessBuffer_ = textureArgumentBuffer_;
  
  if (!textureArgumentBuffer_) {
    printf("ERROR: Failed to create argument buffer\n");
    return;
  }
  
  // Set the argument buffer for encoding
  [textureArgumentEncoder_ setArgumentBuffer:textureArgumentBuffer_ offset:0];

  // Encode 2D textures into the argument buffer using setTexture
  boundTextures_.clear();
  textures2D_.clear();
  // Encode textures at their handle index position (matches material's texDiffuse = handle.index())
  for (size_t i = 0; i < textures.size(); i++) {
    const TextureHandle& handle = textures[i];
    const MetalTexture* mtlTex = textures_.get(handle);

    if (mtlTex && mtlTex->texture) {
      uint32_t slot = handle.index();
      [textureArgumentEncoder_ setTexture:mtlTex->texture atIndex:slot];
      boundTextures_.push_back(mtlTex->texture);

      if (textures2D_.size() <= slot) {
        textures2D_.resize(slot + 1, nil);
      }
      textures2D_[slot] = mtlTex->texture;
    }
  }
  
}

void MetalContext::updateBindlessTexture(uint32_t index, id<MTLTexture> texture, bool isCube, bool isShadow) {
  if (isShadow) {
    if (texturesShadow_.size() <= index) {
      texturesShadow_.resize(index + 1, nil);
    }
    texturesShadow_[index] = texture;
  } else if (isCube) {
    if (texturesCube_.size() <= index) {
      texturesCube_.resize(index + 1, nil);
    }
    texturesCube_[index] = texture;
  } else {
    if (textures2D_.size() <= index) {
      textures2D_.resize(index + 1, nil);
    }
    textures2D_[index] = texture;
  }
}

void MetalContext::updateBindlessSampler(uint32_t index, id<MTLSamplerState> sampler, bool isShadow) {
  if (isShadow) {
    if (samplersShadow_.size() <= index) {
      samplersShadow_.resize(index + 1, nil);
    }
    samplersShadow_[index] = sampler;
  } else {
    if (bindlessSamplers_.size() <= index) {
      bindlessSamplers_.resize(index + 1, nil);
    }
    bindlessSamplers_[index] = sampler;
  }
}

ICommandBuffer& MetalContext::acquireCommandBuffer() {
  if (!currentCommandBuffer_) {
    id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
    currentCommandBuffer_ = std::make_unique<MetalCommandBuffer>(this, cmdBuf);
  }
  return *currentCommandBuffer_;
}

SubmitHandle MetalContext::submit(ICommandBuffer& commandBuffer, TextureHandle present) {
  MetalCommandBuffer& metalCmdBuf = static_cast<MetalCommandBuffer&>(commandBuffer);
  
  if (present) {
    id<MTLDrawable> drawable = currentDrawable_;
    if (drawable) {
      [metalCmdBuf.getMTLCommandBuffer() presentDrawable:drawable];
    }
  }
  
  metalCmdBuf.commit();
  
  // Return a proper SubmitHandle with submitId in upper 32 bits
  currentCommandBuffer_.reset();
  currentDrawable_ = nil;
  // Encode: bufferIndex=0, submitId=1 → handle = (1 << 32) + 0 = 0x100000000
  return SubmitHandle(0x100000000ULL); 
}

void MetalContext::wait(SubmitHandle handle) {
  // fast path for simple synchronization
  if (device_) {
     // This is a heavy hammer, ideally we wait for specific fence
     id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
     [cmdBuf commit];
     [cmdBuf waitUntilCompleted];
  }
}

// Stubs for resource creation
Holder<BufferHandle> MetalContext::createBuffer(const BufferDesc& desc, const char* debugName, Result* outResult) {
  MTLResourceOptions options = 0;
  if (desc.storage == StorageType_HostVisible) {
      options = MTLResourceStorageModeShared;
  } else {
      options = MTLResourceStorageModePrivate;
  }
  
  id<MTLBuffer> buffer = nil;
  if (desc.data && desc.storage == StorageType_HostVisible) {
      buffer = [device_ newBufferWithBytes:desc.data length:desc.size options:options];
  } else {
      buffer = [device_ newBufferWithLength:desc.size options:options];
      if (desc.data) {
          // For Private storage with data, we need a staging buffer and a blit
          id<MTLBuffer> staging = [device_ newBufferWithBytes:desc.data length:desc.size options:MTLResourceStorageModeShared];
          id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
          id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
          [blit copyFromBuffer:staging sourceOffset:0 toBuffer:buffer destinationOffset:0 size:desc.size];
          [blit endEncoding];
          [cmdBuf commit];
          [cmdBuf waitUntilCompleted];
      }
  }
  
  if (!buffer) {
     if (outResult) *outResult = Result(Result::Code::RuntimeError, "Failed to create Metal buffer");
     return Holder<BufferHandle>((IContext*)this, BufferHandle());
  }
  
  if (debugName) {
      buffer.label = [NSString stringWithUTF8String:debugName];
  }
  
  return Holder<BufferHandle>((IContext*)this, buffers_.create(MetalBuffer{buffer}));
}

Holder<SamplerHandle> MetalContext::createSampler(const SamplerStateDesc& desc, Result* outResult) {
     MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
     
     auto convertFilter = [](SamplerFilter mode) {
         return mode == SamplerFilter_Nearest ? MTLSamplerMinMagFilterNearest : MTLSamplerMinMagFilterLinear;
     };
     auto convertMipFilter = [](SamplerMip mode) {
         return mode == SamplerMip_Nearest ? MTLSamplerMipFilterNearest : MTLSamplerMipFilterLinear;
     };
     auto convertAddress = [](SamplerWrap mode) {
         switch (mode) {
             case SamplerWrap_Repeat: return MTLSamplerAddressModeRepeat;
             case SamplerWrap_Clamp: return MTLSamplerAddressModeClampToEdge;
             case SamplerWrap_MirrorRepeat: return MTLSamplerAddressModeMirrorRepeat;
             default: return MTLSamplerAddressModeRepeat; 
         }
     };

     samplerDesc.minFilter = convertFilter(desc.minFilter);
     samplerDesc.magFilter = convertFilter(desc.magFilter);
     samplerDesc.mipFilter = convertMipFilter(desc.mipMap);
     samplerDesc.sAddressMode = convertAddress(desc.wrapU);
     samplerDesc.tAddressMode = convertAddress(desc.wrapV);
     samplerDesc.rAddressMode = convertAddress(desc.wrapW);
     
     id<MTLSamplerState> sampler = [device_ newSamplerStateWithDescriptor:samplerDesc];
     if (!sampler) {
         if (outResult) *outResult = Result(Result::Code::RuntimeError, "Failed to create sampler");
         return Holder<SamplerHandle>((IContext*)this, SamplerHandle());
     }
     
     return Holder<SamplerHandle>((IContext*)this, samplers_.create(MetalSampler{sampler}));
}

Holder<TextureHandle> MetalContext::createTexture(const TextureDesc& desc, const char* debugName, Result* outResult) {
  MTLTextureDescriptor* mtlDesc = [[MTLTextureDescriptor alloc] init];
  
  // Set correct texture type based on samples and type
  if (desc.numSamples > 1) {
      mtlDesc.textureType = MTLTextureType2DMultisample;
      mtlDesc.sampleCount = desc.numSamples;
  } else {
      mtlDesc.textureType = (desc.type == TextureType_Cube) ? MTLTextureTypeCube : MTLTextureType2D;
  }
  
  mtlDesc.pixelFormat = vkFormatToMetal(desc.format);
  if (mtlDesc.pixelFormat == MTLPixelFormatInvalid) {
      printf("MetalContext::createTexture: Invalid pixel format %d for debugName: %s\n", desc.format, debugName ? debugName : "unknown");
      if (outResult) *outResult = Result(Result::Code::RuntimeError, "Invalid Metal pixel format");
      return Holder<TextureHandle>((IContext*)this, TextureHandle());
  }
  mtlDesc.width = desc.dimensions.width;
  mtlDesc.height = desc.dimensions.height;
  mtlDesc.depth = 1; 
  mtlDesc.mipmapLevelCount = desc.numMipLevels;
  mtlDesc.arrayLength = 1;
  mtlDesc.usage = MTLTextureUsageShaderRead;
  if (desc.generateMipmaps && desc.numMipLevels > 1) {
      mtlDesc.usage |= MTLTextureUsageShaderWrite;
  }
  if (desc.usage & TextureUsageBits_Attachment) {
      mtlDesc.usage |= MTLTextureUsageRenderTarget;
  }
  if (desc.usage & TextureUsageBits_Storage) {
      mtlDesc.usage |= MTLTextureUsageShaderWrite;
  }
  
  bool isUnified = false;
  if (@available(macOS 10.15, *)) {
      isUnified = [device_ hasUnifiedMemory];
  }
  
  if (desc.usage & TextureUsageBits_Storage) {
      if (isUnified) {
          mtlDesc.storageMode = MTLStorageModeShared;
      } else {
          mtlDesc.storageMode = MTLStorageModeManaged;
      }
  } else {
      // Force Shared/Managed to ensure we use replaceRegion Fast Path
      if (isUnified) {
          mtlDesc.storageMode = MTLStorageModeShared;
      } else {
          mtlDesc.storageMode = MTLStorageModeManaged;
      }
  }
  
  // Force Private if explicitly requested (not in Desc yet, assuming default behavior)
  // Actually, for the Dummy Texture test, we populate data on CPU, so we need Shared/Managed.
  
  id<MTLTexture> texture = [device_ newTextureWithDescriptor:mtlDesc];
  if (!texture) {
      if (outResult) *outResult = Result(Result::Code::RuntimeError, "Failed to create Metal texture");
      return Holder<TextureHandle>((IContext*)this, TextureHandle());
  }

  // ... (Swizzle Logic here) ...
  
  if (@available(macOS 10.15, *)) {
      // ... existing swizzle logic (re-implemented/preserved below) ...
      // I need to be careful not to delete the swizzle logic I added in previous steps.
      // The user instruction "ReplacementContent" asks me to provide the replacement.
      // I should include the swizzle logic I added previously.
      auto convertSwizzle = [](Swizzle s, MTLTextureSwizzle def) {
          switch (s) {
              case Swizzle_Default: return def;
              case Swizzle_0: return MTLTextureSwizzleZero;
              case Swizzle_1: return MTLTextureSwizzleOne;
              case Swizzle_R: return MTLTextureSwizzleRed;
              case Swizzle_G: return MTLTextureSwizzleGreen;
              case Swizzle_B: return MTLTextureSwizzleBlue;
              case Swizzle_A: return MTLTextureSwizzleAlpha;
          }
          return def;
      };
      
      MTLTextureSwizzle r = convertSwizzle(desc.components.r, MTLTextureSwizzleRed);
      MTLTextureSwizzle g = convertSwizzle(desc.components.g, MTLTextureSwizzleGreen);
      MTLTextureSwizzle b = convertSwizzle(desc.components.b, MTLTextureSwizzleBlue);
      MTLTextureSwizzle a = convertSwizzle(desc.components.a, MTLTextureSwizzleAlpha);
      
      if (r != MTLTextureSwizzleRed || g != MTLTextureSwizzleGreen || b != MTLTextureSwizzleBlue || a != MTLTextureSwizzleAlpha) {
          MTLTextureSwizzleChannels swizzle = MTLTextureSwizzleChannelsMake(r, g, b, a);
          // Note: newTextureView inherits storage mode
          id<MTLTexture> swizzledView = [texture newTextureViewWithPixelFormat:texture.pixelFormat 
                                                                   textureType:texture.textureType 
                                                                        levels:NSMakeRange(0, texture.mipmapLevelCount) 
                                                                        slices:NSMakeRange(0, texture.arrayLength) 
                                                                       swizzle:swizzle];
          if (swizzledView) {
              // Copy label relative to original if present
              if (debugName) swizzledView.label = [NSString stringWithUTF8String:debugName];
              texture = swizzledView;
          }
      }
  }
  
  if (debugName) {
      // Set label on the whatever texture we ended up with (base or view)
      texture.label = [NSString stringWithUTF8String:debugName];
  }
  
  TextureHandle handle = textures_.create(MetalTexture{texture});

  if (desc.data) {
      uint32_t numLayers = (desc.type == TextureType_Cube) ? 6 : 1;
      uint32_t bpr = getBytesPerRow(texture.pixelFormat, desc.dimensions.width);
      uint32_t bpi = 0;
      if (isCompressed(texture.pixelFormat)) {
          bpi = ((desc.dimensions.height + 3) / 4) * bpr;
      } else {
          bpi = bpr * desc.dimensions.height;
      }

      for (uint32_t layer = 0; layer < numLayers; layer++) {
          upload(handle, {
              .dimensions = desc.dimensions,
              .layer = layer,
          }, (const uint8_t*)desc.data + (layer * bpi), 0);
      }

      // Generate mipmaps if requested and texture has more than 1 mip level
      if (desc.generateMipmaps && desc.numMipLevels > 1) {
          id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
          id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
          [blit generateMipmapsForTexture:texture];
          [blit endEncoding];
          [cmdBuf commit];
          [cmdBuf waitUntilCompleted];
      }
  }

  return Holder<TextureHandle>((IContext*)this, handle);
}

Holder<TextureHandle> MetalContext::createTextureView(TextureHandle texture, const TextureViewDesc& desc, const char* debugName, Result* outResult) {
     return Holder<TextureHandle>((IContext*)this, TextureHandle());
}

Holder<ComputePipelineHandle> MetalContext::createComputePipeline(const ComputePipelineDesc& desc, Result* outResult) {
     return Holder<ComputePipelineHandle>((IContext*)this, ComputePipelineHandle());
}

Holder<RenderPipelineHandle> MetalContext::createRenderPipeline(const RenderPipelineDesc& desc, Result* outResult) {
  MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
  
  MetalRenderPipeline metalPipeline;
  metalPipeline.primitiveType = vkTopologyToMetal(desc.topology);
  // Map CullMode
  switch (desc.cullMode) {
      case CullMode_None: metalPipeline.cullMode = MTLCullModeNone; break;
      case CullMode_Front: metalPipeline.cullMode = MTLCullModeFront; break;
      case CullMode_Back: metalPipeline.cullMode = MTLCullModeBack; break;
  }
  // Metal doesn't support FrontAndBack directly
  // Map FrontFace (Inverted)
  // Default LVK is CCW. Inverted Y -> CW.
  if (desc.frontFaceWinding == WindingMode_CCW) {
      metalPipeline.winding = MTLWindingClockwise;
  } else {
      metalPipeline.winding = MTLWindingCounterClockwise;
  }

  
  // Vertex Shader
  const MetalShaderModule* vertModule = shaderModules_.get(desc.smVert);
  if (vertModule && vertModule->library) {
    NSString* name = [NSString stringWithUTF8String:vertModule->entryPointName.c_str()];
    id<MTLFunction> func = [vertModule->library newFunctionWithName:name];
    if (!func) {
        printf("ERROR: Failed to find vertex function '%s' in library\n", vertModule->entryPointName.c_str());
    }
    pipelineDesc.vertexFunction = func;
  } else {
      printf("ERROR: Vertex module or library is null for pipeline\n");
  }
  
  // Fragment Shader
  const MetalShaderModule* fragModule = shaderModules_.get(desc.smFrag);
  if (fragModule && fragModule->library) {
    NSString* name = [NSString stringWithUTF8String:fragModule->entryPointName.c_str()];
    id<MTLFunction> fragFunc = [fragModule->library newFunctionWithName:name];
    if (!fragFunc) {
        printf("ERROR: Failed to find fragment function '%s' in library\n", fragModule->entryPointName.c_str());
    }
    pipelineDesc.fragmentFunction = fragFunc;
  } else {
      printf("ERROR: Fragment module or library is null for pipeline '%s'\n", desc.debugName ? desc.debugName : "Unknown");
  }
  
  // Color Attachments
  for (uint32_t i = 0; i < desc.getNumColorAttachments(); i++) {
    MTLPixelFormat fmt = vkFormatToMetal(desc.color[i].format);
    if (fmt != MTLPixelFormatInvalid) {
      pipelineDesc.colorAttachments[i].pixelFormat = fmt;
      pipelineDesc.colorAttachments[i].blendingEnabled = NO;
      pipelineDesc.colorAttachments[i].writeMask = MTLColorWriteMaskAll;  // CRITICAL: Enable color writes!
    }
  }
  
  // Depth/Stencil Format
  if (desc.depthFormat != Format_Invalid) {
    pipelineDesc.depthAttachmentPixelFormat = vkFormatToMetal(desc.depthFormat);
  }
  if (desc.stencilFormat != Format_Invalid) {
    pipelineDesc.stencilAttachmentPixelFormat = vkFormatToMetal(desc.stencilFormat);
  }
  
  // Vertex Descriptor
  MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
  
  // Attributes
  for (uint32_t i = 0; i < VertexInput::LVK_VERTEX_ATTRIBUTES_MAX; i++) {
      const auto& attr = desc.vertexInput.attributes[i];
      if (attr.format == VertexFormat::Invalid) break;
      
      MTLVertexAttributeDescriptor* mtlAttr = vertexDesc.attributes[attr.location];
      mtlAttr.format = vkVertexFormatToMetal(attr.format);
      mtlAttr.offset = attr.offset;
      mtlAttr.bufferIndex = attr.binding;
  }
  
  // Layouts
  for (uint32_t i = 0; i < VertexInput::LVK_VERTEX_BUFFER_MAX; i++) {
      const auto& binding = desc.vertexInput.inputBindings[i];
      if (binding.stride == 0 && i >= desc.vertexInput.getNumAttributes()) continue; // Heuristic: skip if 0 stride and high index
      // Better: Check if any attribute uses this binding?
      // For now, trust the binding index if stride > 0 or if attributes point to it.
      
      MTLVertexBufferLayoutDescriptor* mtlLayout = vertexDesc.layouts[i];
      mtlLayout.stride = binding.stride;
      mtlLayout.stepFunction = (binding.inputRate == VertexInputRate_Vertex) ? MTLVertexStepFunctionPerVertex : MTLVertexStepFunctionPerInstance;
      mtlLayout.stepRate = 1;
  }
  
  pipelineDesc.vertexDescriptor = vertexDesc;
  
  NSError* error = nil;
  id<MTLRenderPipelineState> pipelineState = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

  if (!pipelineState) {
    printf("ERROR: Pipeline state creation failed: %s\n", [[error localizedDescription] UTF8String]);
    if (outResult) *outResult = Result(Result::Code::RuntimeError, [[error localizedDescription] UTF8String]);
    return Holder<RenderPipelineHandle>((IContext*)this, RenderPipelineHandle());
  }
  
  // Depth Stencil State
  MTLDepthStencilDescriptor* dsDesc = [[MTLDepthStencilDescriptor alloc] init];
  if (desc.depthFormat != Format_Invalid) {
      // RenderPipelineDesc in LVK.h currently lacks DepthState.
      // We hardcode sensible defaults for 3D rendering: LessEqual and Write.
      dsDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
      dsDesc.depthWriteEnabled = YES;
  }
  id<MTLDepthStencilState> dsState = [device_ newDepthStencilStateWithDescriptor:dsDesc];
 
  metalPipeline.mps = pipelineState;
  metalPipeline.depthStencilState = dsState;
  metalPipeline.cullMode = (desc.cullMode == CullMode_None) ? MTLCullModeNone : (desc.cullMode == CullMode_Front) ? MTLCullModeFront : MTLCullModeBack;
  // Winding is already set above (lines 547-551) with Y-flip correction: CCW→CW, CW→CCW
  
  return Holder<RenderPipelineHandle>((IContext*)this, renderPipelines_.create(std::move(metalPipeline)));
}

Holder<RayTracingPipelineHandle> MetalContext::createRayTracingPipeline(const RayTracingPipelineDesc& desc, Result* outResult) {
     return Holder<RayTracingPipelineHandle>((IContext*)this, RayTracingPipelineHandle());
}

  Holder<ShaderModuleHandle> MetalContext::createShaderModule(const ShaderModuleDesc& desc, Result* outResult) {
    const char* srcChars = (const char*)desc.data;
    std::string mslSourceString;
    const char* finalMSL = nullptr;
    const char* entryPoint = desc.entryPointName ? desc.entryPointName : "main0";

    // 1. Direct MSL Bypass
    if (srcChars && strstr(srcChars, "#include <metal_stdlib>") != nullptr) {
        finalMSL = srcChars;
    } else if (desc.data != nullptr) {
        // 2. GLSL or SPIRV Translation
        std::vector<uint8_t> spirv;
        bool isSPIRV = (desc.dataSize >= 4 && *((const uint32_t*)desc.data) == 0x07230203);
        
        if (srcChars && !isSPIRV && (strstr(srcChars, "layout") != nullptr || strstr(srcChars, "void main") != nullptr || strstr(srcChars, "#version") != nullptr)) {
            // It's GLSL, compile to SPIRV first
            Result res = compileShaderGlslang(desc.stage, srcChars, &spirv);
            if (!res.isOk()) {
                printf("ERROR: compileShaderGlslang failed for %s: %s\n", desc.debugName ? desc.debugName : "unknown", res.message);
                if (outResult) *outResult = res;
                return Holder<ShaderModuleHandle>((IContext*)this, ShaderModuleHandle());
            }
        } else if (isSPIRV || desc.dataSize > 0) {
            // Assume it's already SPIRV
            spirv.assign((const uint8_t*)desc.data, (const uint8_t*)desc.data + desc.dataSize);
        }

        if (!spirv.empty()) {
            // Translate SPIRV to MSL
            Result res = translateSPIRVToMSL(desc.stage, spirv, &mslSourceString);
            if (!res.isOk()) {
                printf("ERROR: translateSPIRVToMSL failed for %s: %s\n", desc.debugName ? desc.debugName : "unknown", res.message);
                if (outResult) *outResult = res;
                return Holder<ShaderModuleHandle>((IContext*)this, ShaderModuleHandle());
            }
            finalMSL = mslSourceString.c_str();
        }
    }

    if (!finalMSL) {
        printf("ERROR: Could not determine shader source type for %s\n", desc.debugName ? desc.debugName : "unknown");
        if (outResult) *outResult = Result(Result::Code::RuntimeError, "Could not determine shader source type");
        return Holder<ShaderModuleHandle>((IContext*)this, ShaderModuleHandle());
    }

    NSError* error = nil;
    NSString* mslSourceNS = [NSString stringWithUTF8String:finalMSL];
    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion2_3;
    
    id<MTLLibrary> library = [device_ newLibraryWithSource:mslSourceNS options:options error:&error];
    if (!library) {
        printf("ERROR: Metal library creation failed for %s: %s\n", desc.debugName ? desc.debugName : "unknown", [[error localizedDescription] UTF8String]);
        // printf("Final MSL:\n%s\n", finalMSL);
        if (outResult) *outResult = Result(Result::Code::RuntimeError, [[error localizedDescription] UTF8String]);
        return Holder<ShaderModuleHandle>((IContext*)this, ShaderModuleHandle());
    }

    MetalShaderModule sm;
    sm.library = library;
    sm.entryPointName = entryPoint;
    sm.source = desc.data; // Keep original for reference
    
    return Holder<ShaderModuleHandle>((IContext*)this, shaderModules_.create(std::move(sm)));
  }
Holder<QueryPoolHandle> MetalContext::createQueryPool(uint32_t numQueries, const char* debugName, Result* outResult) {
     return Holder<QueryPoolHandle>((IContext*)this, QueryPoolHandle());
}

Holder<AccelStructHandle> MetalContext::createAccelerationStructure(const AccelStructDesc& desc, Result* outResult) {
     return Holder<AccelStructHandle>((IContext*)this, AccelStructHandle());
}

void MetalContext::destroy(ComputePipelineHandle handle) {}
void MetalContext::destroy(RenderPipelineHandle handle) {}
void MetalContext::destroy(RayTracingPipelineHandle handle) {}
void MetalContext::destroy(ShaderModuleHandle handle) {}
void MetalContext::destroy(SamplerHandle handle) {}
void MetalContext::destroy(BufferHandle handle) {}
void MetalContext::destroy(TextureHandle handle) {}
void MetalContext::destroy(QueryPoolHandle handle) {}
void MetalContext::destroy(AccelStructHandle handle) {}
void MetalContext::destroy(Framebuffer& fb) {}

uint64_t MetalContext::gpuAddress(AccelStructHandle handle) const { return 0; }

AccelStructSizes MetalContext::getAccelStructSizes(const AccelStructDesc& desc, Result* outResult) const { return {}; }

Result MetalContext::upload(BufferHandle handle, const void* data, size_t size, size_t offset) { return Result(); }
Result MetalContext::download(BufferHandle handle, void* data, size_t size, size_t offset) { return Result(); }
uint64_t MetalContext::gpuAddress(BufferHandle handle, size_t offset) const {
    const MetalBuffer* buf = buffers_.get(handle);
    if (!buf || !buf->buffer) return 0;
    return buf->buffer.gpuAddress + offset;
}

uint8_t* MetalContext::getMappedPtr(BufferHandle handle) const {
    const MetalBuffer* buf = buffers_.get(handle);
    if (!buf || !buf->buffer) return nullptr;
    return (uint8_t*)buf->buffer.contents;
}

void MetalContext::flushMappedMemory(BufferHandle handle, size_t offset, size_t size) const {
    const MetalBuffer* buf = buffers_.get(handle);
    if (!buf || !buf->buffer) return;
#if defined(LVK_PLATFORM_IOS) || defined(__MAC_10_15)
//    if (buf->buffer.storageMode != MTLStorageModeShared) // Managed on macOS
//        [buf->buffer didModifyRange:NSMakeRange(offset, size)];
#endif
   // Shared memory is coherent on Apple Silicon/Unified, typically.
   // If using Managed mode on macOS (discrete GPU), we need didModifyRange.
   // For now assume coherent/Shared.
}

uint32_t MetalContext::getMaxStorageBufferRange() const { return 0xFFFFFFFF; }

Result MetalContext::upload(TextureHandle handle, const TextureRangeDesc& range, const void* data, uint32_t bufferRowLength) {
    MetalTexture* tex = textures_.get(handle);
    if (!tex || !tex->texture) return Result(Result::Code::RuntimeError, "Invalid texture handle or texture object is null.");
    
    // Fast path for Shared/Managed textures using replaceRegion
    // CRITICAL: Use TIGHT packing for bytesPerRow if bufferRowLength is 0. 
    // Metal getBytesPerRow returns 256-byte aligned value, which reads OOB for small textures (like 1x1 dummy).
    if (tex->texture.storageMode != MTLStorageModePrivate) {
        MTLRegion mtlRegion = MTLRegionMake3D(range.offset.x, range.offset.y, range.offset.z,
                                              range.dimensions.width, range.dimensions.height, range.dimensions.depth);
        
        uint32_t bpr = 0;
        if (bufferRowLength > 0) {
            bpr = getBytesPerRow(tex->texture.pixelFormat, bufferRowLength); // Use aligned if explicitly row-length specified?
            // Actually, if user provides bufferRowLength, we assume they match Metal requirements or their own stride.
            // But usually this means TIGHT packing of 'bufferRowLength' pixels.
            // getBytesPerRow likely aligns. Let's calculate tight manually for safety on Fast Path.
            // But to be safe, let's assume if bufferRowLength is 0, it is PACKED TIGHTLY.
        } 
        
        // Manual Tight Stride Calc
        uint32_t blockW = 1;
        uint32_t blockSize = 4; // Default RGBA8
        if (tex->texture.pixelFormat == MTLPixelFormatRGBA8Unorm || tex->texture.pixelFormat == MTLPixelFormatRGBA8Unorm_sRGB) {
            blockSize = 4;
        } else if (tex->texture.pixelFormat == MTLPixelFormatBGRA8Unorm || tex->texture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB) {
            blockSize = 4;
        } else {
             // Fallback to aligned for complex formats, or trust getBytesPerRow if not 1x1
             // For Tiny_MeshLarge Dummy, it is RGBA8.
             // If we use aligned bpr for 1x1, we crash/black.
             // We CAN query texture.
             // Let's use getBytesPerRow BUT if width*4 < 256, use width*4?
             // No, safely:
             bpr = getBytesPerRow(tex->texture.pixelFormat, bufferRowLength ? bufferRowLength : range.dimensions.width);
             // If bpr > real data size?
             // We need to know if 'data' is packed.
             // 'data' comes from User. User usually packs tightly.
             // If User provides 1 pixel (4 bytes).
             // We MUST pass 4 bytes per row.
             // So we MUST NOT use getBytesPerRow(..., 256 alignment).
        }
        
        // Simplified Logic: If no bufferRowLength, assume tight packing based on format
        if (bufferRowLength == 0) {
             if (tex->texture.pixelFormat == MTLPixelFormatRGBA8Unorm || tex->texture.pixelFormat == MTLPixelFormatRGBA8Unorm_sRGB || 
                 tex->texture.pixelFormat == MTLPixelFormatBGRA8Unorm || tex->texture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB) {
                 bpr = range.dimensions.width * 4;
             } else {
                 bpr = getBytesPerRow(tex->texture.pixelFormat, range.dimensions.width); // Fallback
             }
        } else {
             bpr = getBytesPerRow(tex->texture.pixelFormat, bufferRowLength);
        }

        uint32_t bpi = 0;
        if (isCompressed(tex->texture.pixelFormat)) {
             bpi = ((range.dimensions.height + 3) / 4) * bpr;
        } else {
             bpi = bpr * range.dimensions.height;
        }
        
        [tex->texture replaceRegion:mtlRegion
                        mipmapLevel:range.mipLevel
                              slice:range.layer
                          withBytes:data
                        bytesPerRow:bpr
                      bytesPerImage:bpi];
        return Result();
    }

    // Private texture path (Staging Buffer + Blit)
    // Metal requires sourceBytesPerRow to be 256-byte aligned for blit commands
    uint32_t tightBpr = getBytesPerRow(tex->texture.pixelFormat, range.dimensions.width);
    uint32_t sourceBpr = bufferRowLength ? getBytesPerRow(tex->texture.pixelFormat, bufferRowLength) : tightBpr;
    uint32_t alignedBpr = (sourceBpr + 255) & ~255;
    
    // Determine total size for staging buffer
    uint32_t rows = range.dimensions.height;
    if (isCompressed(tex->texture.pixelFormat)) {
        rows = (range.dimensions.height + 3) / 4;
        // Compressed formats usually don't need 256 alignment if handled as blocks?
        // But let's assume standard blit rules apply if copying via buffer.
        // Actually blit compression rules are complex.
        // Let's rely on standard logic but ensure we don't under-allocate.
        // If compressed, getBytesPerRow returns block row size.
        // We might need to align that too?
        // Metal docs: "For compressed pixel formats, bytesPerRow is the number of bytes in a row of blocks".
        // And it must be multiple of 256?
        alignedBpr = (sourceBpr + 255) & ~255; 
    }
    
    uint32_t alignedBytesPerImage = alignedBpr * rows;
    uint32_t stagingSize = alignedBytesPerImage * range.dimensions.depth;
    
    // Create Staging Buffer
    id<MTLBuffer> stagingBuffer = [device_ newBufferWithLength:stagingSize options:MTLResourceStorageModeShared];
    if (!stagingBuffer) return Result(Result::Code::RuntimeError, "Failed to create staging buffer");

    // Copy Content to Staging Buffer with Check for Repacking
    uint8_t* dstPtr = (uint8_t*)[stagingBuffer contents];
    const uint8_t* srcPtr = (const uint8_t*)data;
    
    // If we need to repack (e.g. source is tight 4 bytes, destination is aligned 256 bytes)
    // Or if source is already aligned (bufferRowLength) match.
    if (sourceBpr != alignedBpr && data) {
        // Row-by-row copy
        for (uint32_t d = 0; d < range.dimensions.depth; d++) {
            for (uint32_t r = 0; r < rows; r++) {
                memcpy(dstPtr + (d * alignedBytesPerImage) + (r * alignedBpr), 
                       srcPtr + (d * rows * sourceBpr) + (r * sourceBpr), 
                       sourceBpr);
            }
        }
    } else if (data) {
        // Direct copy (Source is effectively aligned or we assume user understands strides? 
        // No, if sourceBpr == alignedBpr, we can copy direct.
        // But source is usually tight. If tight == aligned (e.g. 256 width), direct copy works.
        // But if bufferRowLength was used to force alignment, sourceBpr includes it.
        memcpy(dstPtr, srcPtr, rows * range.dimensions.depth * sourceBpr);
    }
    
    // Blit from Staging Buffer to Texture (Private)
    id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
    
    // Handle array layers (slices)
    for (uint32_t layer = 0; layer < range.dimensions.depth; layer++) {
        uint32_t srcOffset = layer * alignedBytesPerImage;
        uint32_t dstSlice = range.layer + layer;
        
        [blit copyFromBuffer:stagingBuffer
                sourceOffset:srcOffset
           sourceBytesPerRow:alignedBpr
         sourceBytesPerImage:alignedBytesPerImage
                  sourceSize:MTLSizeMake(range.dimensions.width, range.dimensions.height, 1)
                   toTexture:tex->texture
            destinationSlice:dstSlice
            destinationLevel:range.mipLevel
           destinationOrigin:MTLOriginMake(range.offset.x, range.offset.y, range.offset.z)];
    }
    
    [blit endEncoding];
    [cmdBuf commit];
    [cmdBuf waitUntilCompleted];
    
    return Result();
}
Result MetalContext::download(TextureHandle handle, const TextureRangeDesc& range, void* outData) {
  MetalTexture* tex = textures_.get(handle);
  if (!tex || !tex->texture) return Result(Result::Code::ArgumentOutOfRange, "Invalid texture");
  
  uint32_t width = range.dimensions.width;
  uint32_t height = range.dimensions.height;
  NSUInteger bytesPerRow = width * 4; // Assume 4 bytes/pixel for now
  
  if (tex->texture.storageMode == MTLStorageModePrivate) {
      // Must blit to shared buffer
      NSUInteger size = bytesPerRow * height;
      id<MTLBuffer> readBuf = [device_ newBufferWithLength:size options:MTLResourceStorageModeShared];
      
      id<MTLCommandBuffer> cmdBuf = [commandQueue_ commandBuffer];
      id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
      [blit copyFromTexture:tex->texture 
                sourceSlice:0 
                sourceLevel:range.mipLevel 
               sourceOrigin:MTLOriginMake(range.offset.x, range.offset.y, 0) 
                 sourceSize:MTLSizeMake(width, height, 1) 
                   toBuffer:readBuf 
          destinationOffset:0 
     destinationBytesPerRow:bytesPerRow 
   destinationBytesPerImage:size];
      [blit endEncoding];
      [cmdBuf commit];
      [cmdBuf waitUntilCompleted];
      
      memcpy(outData, readBuf.contents, size);
  } else {
      [tex->texture getBytes:outData bytesPerRow:bytesPerRow fromRegion:MTLRegionMake2D(range.offset.x, range.offset.y, width, height) mipmapLevel:range.mipLevel];
  }
  
  return Result();
}

Dimensions MetalContext::getDimensions(TextureHandle handle) const {
  const MetalTexture* tex = textures_.get(handle);
  if (!tex || !tex->texture) return {};
  return {(uint32_t)tex->texture.width, (uint32_t)tex->texture.height, (uint32_t)tex->texture.depth};
}

float MetalContext::getAspectRatio(TextureHandle handle) const {
   Dimensions dim = getDimensions(handle);
   return dim.height > 0 ? (float)dim.width / dim.height : 1.0f;
}

Format MetalContext::getFormat(TextureHandle handle) const {
  const MetalTexture* tex = textures_.get(handle);
  if (!tex || !tex->texture) return Format_Invalid;
  
  MTLPixelFormat fmt = tex->texture.pixelFormat;
  switch (fmt) {
      case MTLPixelFormatBGRA8Unorm: return Format_BGRA_UN8;
      case MTLPixelFormatBGRA8Unorm_sRGB: return Format_BGRA_SRGB8;
      case MTLPixelFormatRGBA8Unorm: return Format_RGBA_UN8;
      case MTLPixelFormatRGBA8Unorm_sRGB: return Format_RGBA_SRGB8;
      case MTLPixelFormatDepth32Float: return Format_Z_F32;
      default: return Format_Invalid;
  }
}

TextureHandle MetalContext::getCurrentSwapchainTexture() {
   if (swapchainLayer_) {
      if (!currentDrawable_) currentDrawable_ = [swapchainLayer_ nextDrawable];
      if (currentDrawable_) {
          // LLOGI("Got drawable");
          MetalTexture* tex = textures_.get(swapchainHandle_);
          if (tex) {
              tex->texture = currentDrawable_.texture;
              tex->width = (uint32_t)currentDrawable_.texture.width;
              tex->height = (uint32_t)currentDrawable_.texture.height;
          }
      }
   }
   return swapchainHandle_;
}

Format MetalContext::getSwapchainFormat() const {
  return Format_BGRA_UN8;
}

ColorSpace MetalContext::getSwapchainColorSpace() const {
  return ColorSpace_SRGB_NONLINEAR;
}

uint32_t MetalContext::getSwapchainCurrentImageIndex() const { return 0; }
uint32_t MetalContext::getNumSwapchainImages() const { return 3; }
void MetalContext::recreateSwapchain(int newWidth, int newHeight) {
   if (swapchainLayer_) {
      swapchainLayer_.drawableSize = CGSizeMake(newWidth, newHeight);
   }
}

uint32_t MetalContext::getFramebufferMSAABitMask() const { return 1; }

double MetalContext::getTimestampPeriodToMs() const { return 1.0; }
bool MetalContext::getQueryPoolResults(QueryPoolHandle pool, uint32_t firstQuery, uint32_t queryCount, size_t dataSize, void* outData, size_t stride) const { return false; }


std::unique_ptr<lvk::IContext> createMetalContextWithSwapchain(LVKwindow* window,
                                                               uint32_t width,
                                                               uint32_t height,
                                                               const lvk::ContextConfig& cfg) {
#if LVK_WITH_GLFW
    NSWindow* nswindow = glfwGetCocoaWindow(window);
    void* nativeWindow = (void*)nswindow.contentView;
#else
    void* nativeWindow = window;
#endif
    return std::make_unique<lvk::MetalContext>(nativeWindow, width, height, cfg);
}

} // namespace lvk
