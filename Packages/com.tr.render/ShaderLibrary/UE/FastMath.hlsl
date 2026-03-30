// 移植自 UE5 FastMath.ush + FastMathThirdParty.ush
// 快速近似超越函数库，针对 GPU ALU 优化
// 原始授权: MIT License, Michal Drobot (Shader Fast Math Lib v0.41)

#ifndef TR_UE_FAST_MATH_INCLUDED
#define TR_UE_FAST_MATH_INCLUDED

//=============================================================================
//  快速 exp / log — 利用 exp2/log2 恒等变换，单条指令完成
//  参考: Persson, "Low-Level Thinking in High-Level Shading Languages", p.27
//=============================================================================

// FastExp: e^x = 2^(x * log2(e)), log2(e) ≈ 1.442695
float  FastExp(float  x) { return exp2(1.442695 * x); }
float2 FastExp(float2 x) { return exp2(1.442695 * x); }
float3 FastExp(float3 x) { return exp2(1.442695 * x); }
float4 FastExp(float4 x) { return exp2(1.442695 * x); }

// FastLog: ln(x) = log2(x) * ln(2), ln(2) ≈ 0.693147
// 注意: 这是粗略近似，精度约 ±5%
float  FastLog(float  x) { return log2(x) * 0.693147; }
float2 FastLog(float2 x) { return log2(x) * 0.693147; }
float3 FastLog(float3 x) { return log2(x) * 0.693147; }
float4 FastLog(float4 x) { return log2(x) * 0.693147; }

//=============================================================================
//  快速算术 — 利用 IEEE 754 浮点位操作
//  在 AMD GCN 架构上验证过，精度-性能权衡良好
//=============================================================================

// 快速倒数平方根，相对误差 ~3.4%，2 ALU
float rsqrtFast(float x)
{
    int i = asint(x);
    i = 0x5f3759df - (i >> 1);
    return asfloat(i);
}

// 快速平方根，相对误差 < 0.4%，1 ALU
float sqrtFast(float x)
{
    int i = asint(x);
    i = 0x1FBD1DF5 + (i >> 1);
    return asfloat(i);
}

// 快速倒数，相对误差 < 0.4%，1 ALU
float rcpFast(float x)
{
    int i = asint(x);
    i = 0x7EF311C2 - i;
    return asfloat(i);
}

// 快速倒数 + 1 次牛顿迭代，相对误差 < 0.02%，3 ALU
float rcpFastNR1(float x)
{
    int i = asint(x);
    i = 0x7EF311C3 - i;
    float xRcp = asfloat(i);
    xRcp = xRcp * (-xRcp * x + 2.0);
    return xRcp;
}

// 快速向量长度 / 归一化
float lengthFast(float3 v)
{
    return sqrtFast(dot(v, v));
}

float3 normalizeFast(float3 v)
{
    return v * rsqrtFast(dot(v, v));
}

//=============================================================================
//  快速三角函数 — 多项式近似
//=============================================================================

// 快速 acos，最大绝对误差 9.0e-3
// Eberly 一阶多项式，输入 [-1,1]，输出 [0, PI]
// 4 VGPR, 12 FR
float acosFast(float inX)
{
    float x = abs(inX);
    float res = -0.156583 * x + (0.5 * PI);
    res *= sqrt(1.0 - x);
    return (inX >= 0) ? res : PI - res;
}

float2 acosFast(float2 x) { return float2(acosFast(x.x), acosFast(x.y)); }
float3 acosFast(float3 x) { return float3(acosFast(x.x), acosFast(x.y), acosFast(x.z)); }
float4 acosFast(float4 x) { return float4(acosFast(x.x), acosFast(x.y), acosFast(x.z), acosFast(x.w)); }

// 快速 asin，与 acosFast 同等开销
float asinFast(float x) { return (0.5 * PI) - acosFast(x); }
float2 asinFast(float2 x) { return float2(asinFast(x.x), asinFast(x.y)); }
float3 asinFast(float3 x) { return float3(asinFast(x.x), asinFast(x.y), asinFast(x.z)); }
float4 asinFast(float4 x) { return float4(asinFast(x.x), asinFast(x.y), asinFast(x.z), asinFast(x.w)); }

// 快速 atan（正值），Eberly 五阶奇多项式，最大绝对误差 1.3e-3
// 4 VGPR, 14 FR，输入 [0, ∞)，输出 [0, PI/2]
float atanFastPos(float x)
{
    float t0 = (x < 1.0) ? x : 1.0 / x;
    float t1 = t0 * t0;
    float poly = 0.0872929;
    poly = -0.301895 + poly * t1;
    poly = 1.0 + poly * t1;
    poly = poly * t0;
    return (x < 1.0) ? poly : (0.5 * PI) - poly;
}

// 快速 atan，输入 [-∞, ∞]，输出 [-PI/2, PI/2]
float atanFast(float x)
{
    float t0 = atanFastPos(abs(x));
    return (x < 0) ? -t0 : t0;
}

float2 atanFast(float2 x) { return float2(atanFast(x.x), atanFast(x.y)); }
float3 atanFast(float3 x) { return float3(atanFast(x.x), atanFast(x.y), atanFast(x.z)); }
float4 atanFast(float4 x) { return float4(atanFast(x.x), atanFast(x.y), atanFast(x.z), atanFast(x.w)); }

// 快速 atan2
float atan2Fast(float y, float x)
{
    float t0 = max(abs(x), abs(y));
    float t1 = min(abs(x), abs(y));
    float t3 = t1 / t0;
    float t4 = t3 * t3;

    t0 =         + 0.0872929;
    t0 = t0 * t4 - 0.301895;
    t0 = t0 * t4 + 1.0;
    t3 = t0 * t3;

    t3 = abs(y) > abs(x) ? (0.5 * PI) - t3 : t3;
    t3 = x < 0 ? PI - t3 : t3;
    t3 = y < 0 ? -t3 : t3;

    return t3;
}

// 高精度 acos，四阶多项式，精度 7e-5 弧度
// [Aberta & Stegun, "Handbook of Mathematical Functions"]
float acosFast4(float inX)
{
    float x1 = abs(inX);
    float x2 = x1 * x1;
    float x3 = x2 * x1;
    float s;

    s = -0.2121144 * x1 + 1.5707288;
    s = 0.0742610 * x2 + s;
    s = -0.0187293 * x3 + s;
    s = sqrt(1.0 - x1) * s;

    return inX >= 0.0 ? s : PI - s;
}

float asinFast4(float x) { return (0.5 * PI) - acosFast4(x); }

//=============================================================================
//  向量角度工具
//=============================================================================

// 两向量间的余弦值（不要求输入归一化）
float CosBetweenVectors(float3 A, float3 B)
{
    return dot(A, B) * rsqrt(dot(A, A) * dot(B, B));
}

float AngleBetweenVectors(float3 A, float3 B)
{
    return acos(CosBetweenVectors(A, B));
}

float AngleBetweenVectorsFast(float3 A, float3 B)
{
    return acosFast(CosBetweenVectors(A, B));
}

// 从浮点数符号位提取 ±1（无分支）
int SignFastInt(float v)
{
    return 1 - int((asuint(v) & 0x80000000) >> 30);
}

int2 SignFastInt(float2 v)
{
    return int2(SignFastInt(v.x), SignFastInt(v.y));
}

#endif // TR_UE_FAST_MATH_INCLUDED
