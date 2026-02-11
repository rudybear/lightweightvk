# LightweightVK
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

cmake_minimum_required(VERSION 3.22)

project(LVKLibrary CXX C)

file(GLOB SRC_FILES LIST_DIRECTORIES false RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.cpp)
file(GLOB HEADER_FILES LIST_DIRECTORIES false RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.h)
if(APPLE)
  file(GLOB SRC_FILES_MM LIST_DIRECTORIES false RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.mm)
  list(APPEND SRC_FILES ${SRC_FILES_MM})
endif()

add_library(LVKLibrary ${SRC_FILES} ${HEADER_FILES})

lvk_setup_groups("${SRC_FILES}")
lvk_setup_groups("${HEADER_FILES}")

target_include_directories(LVKLibrary PUBLIC "${LVK_ROOT_DIR}/lvk")
if(WAYLAND_FOUND)
  target_compile_definitions(LVKLibrary PUBLIC -DLVK_WITH_WAYLAND=1)
endif()

lvk_setup_target(LVKLibrary)
  add_subdirectory(${LVK_ROOT_DIR}/third-party/deps/src/SPIRV-Cross ${CMAKE_BINARY_DIR}/third-party/spirv-cross)
  lvk_set_folder(spirv-cross-core "third-party")
  lvk_set_folder(spirv-cross-glsl "third-party")
  lvk_set_folder(spirv-cross-cpp  "third-party")
  lvk_set_folder(spirv-cross-msl  "third-party")
  lvk_set_folder(spirv-cross-hlsl "third-party")
  lvk_set_folder(spirv-cross-reflect "third-party")
  lvk_set_folder(spirv-cross-util "third-party")

add_subdirectory(vulkan)

target_link_libraries(LVKLibrary PUBLIC LVKVulkan)

if (LVK_WITH_METAL)
  target_sources(LVKLibrary PRIVATE
    metal/MetalContext.mm
    metal/MetalCommandBuffer.mm
    metal/MetalShaderUtils.cpp
  )
  target_link_libraries(LVKLibrary PRIVATE spirv-cross-msl glslang SPIRV glslang-default-resource-limits)

  find_library(METAL_LIBRARY Metal)
  find_library(QUARTZCORE_LIBRARY QuartzCore)
  find_library(FOUNDATION_LIBRARY Foundation)
  find_library(COCOA_LIBRARY Cocoa)
  target_link_libraries(LVKLibrary PUBLIC ${METAL_LIBRARY} ${QUARTZCORE_LIBRARY} ${FOUNDATION_LIBRARY} ${COCOA_LIBRARY})
endif()
if(LVK_WITH_GLFW)
  target_link_libraries(LVKLibrary PUBLIC glfw)
endif()

if(APPLE)
  target_link_libraries(LVKLibrary PRIVATE "-framework Metal" "-framework AppKit" "-framework Foundation" "-framework QuartzCore")
endif()
