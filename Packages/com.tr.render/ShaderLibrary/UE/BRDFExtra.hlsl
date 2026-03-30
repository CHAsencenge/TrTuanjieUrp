// 移植自 UE5 BRDF.ush — 高级漫反射模型 + 环境 BRDF 近似
// 补充 URP Core BRDF.hlsl 中缺少的: Burley/OrenNayar/EON 漫反射, EnvBRDFApprox

#ifndef TR_UE_BRDF_EXTRA_INCLUDED
#define TR_UE_BRDF_EXTRA_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

// URP Core 有 Sq/Pow4 但缺少 Pow5，在此补充
#ifndef TR_POW5_DEFINED
#define TR_POW5_DEFINED
float  Pow5(float  x) { float x2 = x * x; return x2 * x2 * x; }
half   Pow5(half   x) { half  x2 = x * x; return x2 * x2 * x; }
#endif

//=============================================================================
//  BxDFContext — 预计算所有 BRDF 需要的点积
//  通过 rsqrt 技巧避免重复 normalize(H)，节省 ALU
//=============================================================================
struct BxDFContext
{
    half NoV;
    half NoL;
    half VoL;
    half NoH;
    half VoH;
    // 各向异性专用
    half XoV, XoL, XoH;
    half YoV, YoL, YoH;
};

// 各向同性初始化 — 不显式计算 H，用 rsqrt 技巧推导 NoH/VoH
void InitBxDFContext(inout BxDFContext Context, half3 N, half3 V, half3 L)
{
    Context.NoL = dot(N, L);
    Context.NoV = dot(N, V);
    Context.VoL = dot(V, L);
    // H = (V+L)/|V+L|, |V+L|^2 = 2 + 2*VoL
    float InvLenH = rsqrt(2 + 2 * Context.VoL);
    Context.NoH = saturate((Context.NoL + Context.NoV) * InvLenH);
    Context.VoH = saturate(InvLenH + InvLenH * Context.VoL);

    Context.XoV = 0.0; Context.XoL = 0.0; Context.XoH = 0.0;
    Context.YoV = 0.0; Context.YoL = 0.0; Context.YoH = 0.0;
}

// 各向异性初始化 — 额外计算切线/副切线方向的点积
void InitBxDFContext(inout BxDFContext Context, half3 N, half3 X, half3 Y, half3 V, half3 L)
{
    Context.NoL = dot(N, L);
    Context.NoV = dot(N, V);
    Context.VoL = dot(V, L);
    float InvLenH = rsqrt(2 + 2 * Context.VoL);
    Context.NoH = saturate((Context.NoL + Context.NoV) * InvLenH);
    Context.VoH = saturate(InvLenH + InvLenH * Context.VoL);

    Context.XoV = dot(X, V);
    Context.XoL = dot(X, L);
    Context.XoH = (Context.XoL + Context.XoV) * InvLenH;
    Context.YoV = dot(Y, V);
    Context.YoL = dot(Y, L);
    Context.YoH = (Context.YoL + Context.YoV) * InvLenH;
}

// 移动端简化版 — 传入预计算的 NoL，显式 normalize(H)
void InitBxDFContextMobile(inout BxDFContext Context, half3 N, half3 V, half3 L, half NoL)
{
    Context.NoL = NoL;
    Context.NoV = dot(N, V);
    Context.VoL = dot(V, L);
    float3 H = normalize(float3(V + L));
    Context.NoH = max(0, dot(N, H));
    Context.VoH = max(0, dot(V, H));

    Context.XoV = 0.0; Context.XoL = 0.0; Context.XoH = 0.0;
    Context.YoV = 0.0; Context.YoL = 0.0; Context.YoH = 0.0;
}

//=============================================================================
//  高级漫反射模型
//=============================================================================

// [Burley 2012, "Physically-Based Shading at Disney"]
// Disney Burley 漫反射 — 在粗糙表面掠射角增加回射亮度
float3 Diffuse_Burley(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
{
    float FD90 = 0.5 + 2 * VoH * VoH * Roughness;
    float FdV = 1 + (FD90 - 1) * Pow5(1 - NoV);
    float FdL = 1 + (FD90 - 1) * Pow5(1 - NoL);
    return DiffuseColor * ((1 / PI) * FdV * FdL);
}

// [Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"]
// Oren-Nayar 简化版 — 考虑微表面自遮挡的粗糙漫反射
float3 Diffuse_OrenNayar(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
{
    float a = Roughness * Roughness;
    float s = a;
    float s2 = s * s;
    float VoL = 2 * VoH * VoH - 1;       // 二倍角恒等式
    float Cosri = VoL - NoV * NoL;
    float C1 = 1 - 0.5 * s2 / (s2 + 0.33);
    float C2 = 0.45 * s2 / (s2 + 0.09) * Cosri * (Cosri >= 0 ? rcp(max(NoL, NoV)) : 1);
    return DiffuseColor / PI * (C1 + C2) * (1 + Roughness * 0.5);
}

// [Portsmouth et al. 2025, "EON: A Practical Energy-Preserving Rough Diffuse BRDF"]
// 能量守恒粗糙漫反射 — 基于 Oren-Nayar + Fujii 修正，能量不会随粗糙度丢失
float3 Diffuse_EON(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoL)
{
    // 反照率反转，使 Lambert 和 EON 在相同颜色下外观一致
    float3 Rho = DiffuseColor * (1.0 + (0.189468 - 0.189468 * DiffuseColor) * Roughness);

    // 主塑形项 (Oren-Nayar + Fujii 修正)
    float S = VoL - NoV * NoL;
    float SOverT = max(S * rcp(max(1e-6, max(NoV, NoL))), S);
    const float constant1_FON = 0.5 - 2.0 / (3.0 * PI);
    // AF ≈ 直线近似 rcp(1 + Roughness * constant1_FON)
    float AF = 1 - Roughness * (1 - 1 / (1 + constant1_FON));
    float f_ss = AF * (1 + Roughness * SOverT);

    // 一阶近似多重散射补偿
    const float g1 = 0.262048;
    float GoverPi_V = g1 - g1 * NoV;
    float f_ms = 1.0 - AF * (1 + Roughness * GoverPi_V);
    // Rho_ms ≈ Rho^2
    return Rho * (f_ss + Rho * f_ms) * (1.0 / PI);
}

//=============================================================================
//  EnvBRDFApprox — 纯 ALU 环境 BRDF 近似
//  [Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II"]
//  无需 LUT 纹理查询，适合移动端和前向渲染
//=============================================================================

// 核心 2D 查找表的 ALU 近似 → 返回 (scale, bias)
half2 EnvBRDFApproxLazarov(half Roughness, half NoV)
{
    const half4 c0 = half4(-1, -0.0275, -0.572, 0.022);
    const half4 c1 = half4(1, 0.0425, 1.04, -0.04);
    half4 r = Roughness * c0 + c1;
    half a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    half2 AB = half2(-1.04, 1.04) * a004 + r.zw;
    return AB;
}

// 完整版 — 输入 SpecularColor 和 Roughness，输出环境反射率
half3 EnvBRDFApprox(half3 SpecularColor, half Roughness, half NoV)
{
    half2 AB = EnvBRDFApproxLazarov(Roughness, NoV);
    // 低于 2% 的反射率物理上不可能，视为阴影
    float F90 = saturate(50.0 * SpecularColor.g);
    return SpecularColor * AB.x + F90 * AB.y;
}

// F0/F90 显式版本
half3 EnvBRDFApprox(half3 F0, half3 F90, half Roughness, half NoV)
{
    half2 AB = EnvBRDFApproxLazarov(Roughness, NoV);
    return F0 * AB.x + F90 * AB.y;
}

// 非金属简化版 — 假设 F0 = 0.04 (电介质默认)
half EnvBRDFApproxNonmetal(half Roughness, half NoV)
{
    const half2 c0 = half2(-1, -0.0275);
    const half2 c1 = half2(1, 0.0425);
    half2 r = Roughness * c0 + c1;
    return min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
}

// 完全粗糙简化 — 将高光能量合并到漫反射
void EnvBRDFApproxFullyRough(inout half3 DiffuseColor, inout half3 SpecularColor)
{
    // 来自 EnvBRDFApprox(SpecularColor, 1, 1) ≈ SpecularColor * 0.4524
    DiffuseColor += SpecularColor * 0.45;
    SpecularColor = 0;
}

#endif // TR_UE_BRDF_EXTRA_INCLUDED
