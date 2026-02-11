/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "MetalShaderUtils.h"
#include <glslang/Public/ShaderLang.h>
#include <glslang/Public/ResourceLimits.h>
#include <glslang/SPIRV/GlslangToSpv.h>
#include <vector>
#include <string>
#include <spirv_msl.hpp>

namespace lvk {

static EShLanguage getGlslangLanguage(lvk::ShaderStage stage) {
  switch (stage) {
  case lvk::Stage_Vert: return EShLangVertex;
  case lvk::Stage_Tesc: return EShLangTessControl;
  case lvk::Stage_Tese: return EShLangTessEvaluation;
  case lvk::Stage_Geom: return EShLangGeometry;
  case lvk::Stage_Frag: return EShLangFragment;
  case lvk::Stage_Comp: return EShLangCompute;
  case lvk::Stage_Task: return EShLangTask;
  case lvk::Stage_Mesh: return EShLangMesh;
  case lvk::Stage_RayGen: return EShLangRayGen;
  case lvk::Stage_AnyHit: return EShLangAnyHit;
  case lvk::Stage_ClosestHit: return EShLangClosestHit;
  case lvk::Stage_Miss: return EShLangMiss;
  case lvk::Stage_Intersection: return EShLangIntersect;
  case lvk::Stage_Callable: return EShLangCallable;
  default: return EShLangCount;
  }
}

Result compileShaderGlslang(lvk::ShaderStage stage, const char* code, std::vector<uint8_t>* outSPIRV) {
  if (!outSPIRV) {
    return Result(Result::Code::ArgumentOutOfRange, "outSPIRV is NULL");
  }

  EShLanguage lang = getGlslangLanguage(stage);
  glslang::TShader shader(lang);
  
  const char* str = code;
  shader.setStrings(&str, 1);
  shader.setEnvInput(glslang::EShSourceGlsl, lang, glslang::EShClientVulkan, 100);
  shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_1);
  shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_3);

  TBuiltInResource resources = {};
  resources.maxLights = 32;
  resources.maxClipPlanes = 6;
  resources.maxTextureUnits = 32;
  resources.maxTextureCoords = 32;
  resources.maxVertexAttribs = 64;
  resources.maxVertexUniformComponents = 4096;
  resources.maxVaryingFloats = 64;
  resources.maxVertexTextureImageUnits = 32;
  resources.maxCombinedTextureImageUnits = 80;
  resources.maxTextureImageUnits = 32;
  resources.maxFragmentUniformComponents = 4096;
  resources.maxDrawBuffers = 32;
  resources.maxVertexUniformVectors = 128;
  resources.maxVaryingVectors = 8;
  resources.maxFragmentUniformVectors = 16;
  resources.maxVertexOutputVectors = 16;
  resources.maxFragmentInputVectors = 15;
  resources.minProgramTexelOffset = -8;
  resources.maxProgramTexelOffset = 7;
  resources.maxClipDistances = 8;
  resources.maxComputeWorkGroupCountX = 65535;
  resources.maxComputeWorkGroupCountY = 65535;
  resources.maxComputeWorkGroupCountZ = 65535;
  resources.maxComputeWorkGroupSizeX = 1024;
  resources.maxComputeWorkGroupSizeY = 1024;
  resources.maxComputeWorkGroupSizeZ = 64;
  resources.maxComputeUniformComponents = 1024;
  resources.maxComputeTextureImageUnits = 16;
  resources.maxComputeImageUniforms = 8;
  resources.maxComputeAtomicCounters = 8;
  resources.maxComputeAtomicCounterBuffers = 1;
  resources.maxVaryingComponents = 60;
  resources.maxVertexOutputComponents = 64;
  resources.maxGeometryInputComponents = 64;
  resources.maxGeometryOutputComponents = 128;
  resources.maxFragmentInputComponents = 128;
  resources.maxImageUnits = 8;
  resources.maxCombinedImageUnitsAndFragmentOutputs = 8;
  resources.maxCombinedShaderOutputResources = 8;
  resources.maxImageSamples = 0;
  resources.maxVertexImageUniforms = 0;
  resources.maxTessControlImageUniforms = 0;
  resources.maxTessEvaluationImageUniforms = 0;
  resources.maxGeometryImageUniforms = 0;
  resources.maxFragmentImageUniforms = 8;
  resources.maxCombinedImageUniforms = 8;
  resources.maxGeometryTextureImageUnits = 16;
  resources.maxGeometryOutputVertices = 256;
  resources.maxGeometryTotalOutputComponents = 1024;
  resources.maxGeometryUniformComponents = 1024;
  resources.maxGeometryVaryingComponents = 64;
  resources.maxTessControlInputComponents = 128;
  resources.maxTessControlOutputComponents = 128;
  resources.maxTessControlTextureImageUnits = 16;
  resources.maxTessControlUniformComponents = 1024;
  resources.maxTessControlTotalOutputComponents = 4096;
  resources.maxTessEvaluationInputComponents = 128;
  resources.maxTessEvaluationOutputComponents = 128;
  resources.maxTessEvaluationTextureImageUnits = 16;
  resources.maxTessEvaluationUniformComponents = 1024;
  resources.maxTessPatchComponents = 120;
  resources.maxPatchVertices = 32;
  resources.maxTessGenLevel = 64;
  resources.maxViewports = 16;
  resources.maxVertexAtomicCounters = 0;
  resources.maxTessControlAtomicCounters = 0;
  resources.maxTessEvaluationAtomicCounters = 0;
  resources.maxGeometryAtomicCounters = 0;
  resources.maxFragmentAtomicCounters = 8;
  resources.maxCombinedAtomicCounters = 8;
  resources.maxAtomicCounterBindings = 1;
  resources.maxVertexAtomicCounterBuffers = 0;
  resources.maxTessControlAtomicCounterBuffers = 0;
  resources.maxTessEvaluationAtomicCounterBuffers = 0;
  resources.maxGeometryAtomicCounterBuffers = 0;
  resources.maxFragmentAtomicCounterBuffers = 1;
  resources.maxCombinedAtomicCounterBuffers = 1;
  resources.maxAtomicCounterBufferSize = 16384;
  resources.maxTransformFeedbackBuffers = 4;
  resources.maxTransformFeedbackInterleavedComponents = 64;
  resources.maxCullDistances = 8;
  resources.maxCombinedClipAndCullDistances = 8;
  resources.maxSamples = 4;
  
  resources.maxMeshOutputVerticesNV = 256;
  resources.maxMeshOutputPrimitivesNV = 512;
  resources.maxMeshWorkGroupSizeX_NV = 32;
  resources.maxMeshWorkGroupSizeY_NV = 1;
  resources.maxMeshWorkGroupSizeZ_NV = 1;
  resources.maxTaskWorkGroupSizeX_NV = 32;
  resources.maxTaskWorkGroupSizeY_NV = 1;
  resources.maxTaskWorkGroupSizeZ_NV = 1;
  resources.maxMeshViewCountNV = 4;

  resources.limits.nonInductiveForLoops = true;
  resources.limits.whileLoops = true;
  resources.limits.doWhileLoops = true;
  resources.limits.generalUniformIndexing = true;
  resources.limits.generalAttributeMatrixVectorIndexing = true;
  resources.limits.generalVaryingIndexing = true;
  resources.limits.generalSamplerIndexing = true;
  resources.limits.generalVariableIndexing = true;
  resources.limits.generalConstantMatrixVectorIndexing = true;

  EShMessages messages = (EShMessages)(EShMsgDefault | EShMsgSpvRules | EShMsgVulkanRules);
  const int defaultVersion = 460;

  if (!shader.parse(&resources, defaultVersion, false, messages)) {
     std::string log = "glslang::TShader::parse() failed:\n";
     log += shader.getInfoLog();
     log += "\n";
     log += shader.getInfoDebugLog();
     printf("%s\n", log.c_str());
     return Result(Result::Code::RuntimeError, "glslang::TShader::parse() failed (see stdout)");
  }

  glslang::TProgram program;
  program.addShader(&shader);
  
  if (!program.link(messages)) {
     printf("Shader linking failed:\n%s\n", program.getInfoLog());
     return Result(Result::Code::RuntimeError, "glslang::TProgram::link() failed (see stdout)");
  }

  std::vector<unsigned int> spirv;
  glslang::SpvOptions options;
  options.generateDebugInfo = true;
  options.disableOptimizer = false;
  options.optimizeSize = true;
  options.validate = true;
  
  glslang::GlslangToSpv(*program.getIntermediate(lang), spirv, &options);

  outSPIRV->assign((uint8_t*)spirv.data(), (uint8_t*)spirv.data() + spirv.size() * sizeof(unsigned int));

  return Result();
}

Result translateSPIRVToMSL(lvk::ShaderStage stage, const std::vector<uint8_t>& spirv, std::string* outMSL) {
    if (spirv.empty() || !outMSL) return Result(Result::Code::ArgumentOutOfRange, "Invalid input");
    
    try {
        spirv_cross::CompilerMSL compiler((const uint32_t*)spirv.data(), spirv.size() / 4);
        
        spirv_cross::CompilerMSL::Options options;
        options.platform = spirv_cross::CompilerMSL::Options::macOS;
        options.msl_version = spirv_cross::CompilerMSL::Options::make_msl_version(2, 3);
        compiler.set_msl_options(options);
        
        *outMSL = compiler.compile();
        return Result();
    } catch (const std::exception& e) {
        return Result(Result::Code::RuntimeError, e.what());
    }
}

} // namespace lvk
