// 移植自 UE5 RandomPCG.ush
// 基于 PCG (Permuted Congruential Generator) 的 GPU 随机数生成器
// 使用简化 Feistel 密码替代 xorshift 置换步骤
// 参考: http://jcgt.org/published/0009/03/02/

#ifndef TR_UE_RANDOM_PCG_INCLUDED
#define TR_UE_RANDOM_PCG_INCLUDED

//=============================================================================
//  Rand3DPCG16 — 3D 坐标 → 3×16bit 随机数
//  每分量 8-12 ALU ops，适合需要大量低精度随机数的场景
//  @param p  整数坐标 (有符号也可正常工作)
//  @return   3 个 16bit 随机值 (0–0xffff)
//=============================================================================
uint3 Rand3DPCG16(int3 p)
{
    // 有符号转无符号：对负数也有良好行为
    uint3 v = uint3(p);

    // 线性同余步骤 (LCG)，常数来自 Numerical Recipes
    v = v * 1664525u + 1013904223u;

    // 简化 Feistel 密码: 用 MAD 代替 xorshift
    // 每轮一次 mad，共 6 轮（前 3 轮 + 后 3 轮）
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;

    // 仅高 16 位充分混洗
    return v >> 16u;
}

//=============================================================================
//  Rand3DPCG32 — 3D 坐标 → 3×32bit 随机数
//  比 16bit 版本多一次 xor 步骤，所有 32 位均质量良好
//  @return   3 个 32bit 随机值 (0–0xffffffff)
//=============================================================================
uint3 Rand3DPCG32(int3 p)
{
    uint3 v = uint3(p);

    v = v * 1664525u + 1013904223u;

    // 第一轮 Feistel
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;

    // 高位异或到低位，使全部 32 位都有良好随机性
    v ^= v >> 16u;

    // 第二轮 Feistel
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;

    return v;
}

//=============================================================================
//  Rand4DPCG32 — 4D 坐标 → 4×32bit 随机数
//  适合时空联合随机化 (x, y, z, frame)
//  @return   4 个 32bit 随机值 (0–0xffffffff)
//=============================================================================
uint4 Rand4DPCG32(int4 p)
{
    uint4 v = uint4(p);

    v = v * 1664525u + 1013904223u;

    v.x += v.y * v.w;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v.w += v.y * v.z;

    v ^= (v >> 16u);

    v.x += v.y * v.w;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v.w += v.y * v.z;

    return v;
}

//=============================================================================
//  整数随机值 → [0,1) 浮点转换
//=============================================================================

// 16bit 值 [0, 2^16) → float [0, 1)
float  Rand16ToFloat(uint  Rand16Bits) { return float(Rand16Bits) * (1.0 / 65536.0); }
float2 Rand16ToFloat(uint2 Rand16Bits) { return float2(Rand16Bits) * (1.0 / 65536.0); }
float3 Rand16ToFloat(uint3 Rand16Bits) { return float3(Rand16Bits) * (1.0 / 65536.0); }
float4 Rand16ToFloat(uint4 Rand16Bits) { return float4(Rand16Bits) * (1.0 / 65536.0); }

// 32bit 值 → float [0, 1)，使用高 24 位以兼容低差异序列
float  Rand32ToFloat(uint  Rand32Bits) { return float(Rand32Bits >> 8) * 5.96046447754e-08; }
float2 Rand32ToFloat(uint2 Rand32Bits) { return float2(Rand32Bits >> 8) * 5.96046447754e-08; }
float3 Rand32ToFloat(uint3 Rand32Bits) { return float3(Rand32Bits >> 8) * 5.96046447754e-08; }
float4 Rand32ToFloat(uint4 Rand32Bits) { return float4(Rand32Bits >> 8) * 5.96046447754e-08; }

#endif // TR_UE_RANDOM_PCG_INCLUDED
