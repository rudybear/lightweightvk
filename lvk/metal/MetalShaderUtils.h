/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include "../LVK.h"
#include <vector>

namespace lvk {

Result compileShaderGlslang(lvk::ShaderStage stage,
                            const char* code,
                            std::vector<uint8_t>* outSPIRV);

Result translateSPIRVToMSL(lvk::ShaderStage stage,
                           const std::vector<uint8_t>& spirv,
                           std::string* outMSL);

} // namespace lvk
