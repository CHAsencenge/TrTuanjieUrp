// UE5 高性能 Shader 工具库 — 汇总头文件
// 一次 include 即可使用全部 UE5 移植函数
// 用法: #include "Packages/com.tr.render/ShaderLibrary/UE/UEShaderLibrary.hlsl"

#ifndef TR_UE_SHADER_LIBRARY_INCLUDED
#define TR_UE_SHADER_LIBRARY_INCLUDED

// Phase 1: 基础层 (无交叉依赖)
#include "Packages/com.tr.render/ShaderLibrary/UE/FastMath.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/Hash.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/RandomPCG.hlsl"

// Phase 2: 功能层
#include "Packages/com.tr.render/ShaderLibrary/UE/BRDFExtra.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/MonteCarlo.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/Noise.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/ColorSpaceExtra.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/TonemapExtra.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/SphericalGaussian.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/TextureSamplingExtra.hlsl"

#endif // TR_UE_SHADER_LIBRARY_INCLUDED
