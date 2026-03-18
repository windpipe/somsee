#!/usr/bin/env bash
# Phase 1 빌드 스크립트
# 의존: Vulkan SDK (glslc), Odin

GLSLC=/c/VulkanSDK/1.3.216.0/Bin/glslc
SHADER_DIR=shaders

echo "=== Compiling shaders ==="
$GLSLC -fshader-stage=comp $SHADER_DIR/particle.comp.glsl -o $SHADER_DIR/particle.comp.spv || exit 1
$GLSLC -fshader-stage=vert $SHADER_DIR/particle.vert.glsl -o $SHADER_DIR/particle.vert.spv || exit 1
$GLSLC -fshader-stage=frag $SHADER_DIR/particle.frag.glsl -o $SHADER_DIR/particle.frag.spv || exit 1
echo "Shaders OK"

echo "=== Building Odin ==="
odin build . -out:somsee.exe -o:speed
echo "Done: somsee.exe"
