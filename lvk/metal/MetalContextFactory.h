/*
 * LightweightVK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <lvk/LVK.h>
#include <memory>

namespace lvk {

std::unique_ptr<IContext> createMetalContext(void* window, uint32_t width, uint32_t height, const ContextConfig& cfg);

} // namespace lvk
