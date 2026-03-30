// 移植自 UE5 MonteCarlo.ush
// 蒙特卡洛积分: 正交基构建、重要性采样、MIS 权重

#ifndef TR_UE_MONTE_CARLO_INCLUDED
#define TR_UE_MONTE_CARLO_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

//=============================================================================
//  正交基构建 — 从单一法线向量生成完整 TBN 矩阵
//=============================================================================

// [Duff et al. 2017, "Building an Orthonormal Basis, Revisited"]
// 在 TangentZ.z == 0 处有不连续点，但整体质量最高
float3x3 GetTangentBasis(float3 TangentZ)
{
    const float Sign = TangentZ.z >= 0 ? 1 : -1;
    const float a = -rcp(Sign + TangentZ.z);
    const float b = TangentZ.x * TangentZ.y * a;

    float3 TangentX = { 1 + Sign * a * Sq(TangentZ.x), Sign * b, -Sign * TangentZ.x };
    float3 TangentY = { b, Sign + a * Sq(TangentZ.y), -TangentZ.y };

    return float3x3(TangentX, TangentY, TangentZ);
}

// [Frisvad 2012, "Building an Orthonormal Basis from a 3D Unit Vector Without Normalization"]
// 在 TangentZ.z < -0.9999999 处不连续
float3x3 GetTangentBasisFrisvad(float3 TangentZ)
{
    float3 TangentX;
    float3 TangentY;

    if (TangentZ.z < -0.9999999)
    {
        TangentX = float3(0, -1, 0);
        TangentY = float3(-1, 0, 0);
    }
    else
    {
        float A = 1.0 / (1.0 + TangentZ.z);
        float B = -TangentZ.x * TangentZ.y * A;
        TangentX = float3(1.0 - TangentZ.x * TangentZ.x * A, B, -TangentZ.x);
        TangentY = float3(B, 1.0 - TangentZ.y * TangentZ.y * A, -TangentZ.y);
    }

    return float3x3(TangentX, TangentY, TangentZ);
}

// 切线空间 ↔ 世界空间 变换
float3 TangentToWorld(float3 Vec, float3 TangentZ)
{
    return mul(Vec, GetTangentBasis(TangentZ));
}

float3 WorldToTangent(float3 Vec, float3 TangentZ)
{
    return mul(GetTangentBasis(TangentZ), Vec);
}

//=============================================================================
//  低差异序列
//=============================================================================

// Hammersley 序列 — 用于 IBL 预积分等确定性采样
float2 Hammersley(uint Index, uint NumSamples, uint2 Random)
{
    float E1 = frac((float)Index / NumSamples + float(Random.x & 0xffff) / (1 << 16));
    float E2 = float(reversebits(Index) ^ Random.y) * 2.3283064365386963e-10;
    return float2(E1, E2);
}

float2 Hammersley16(uint Index, uint NumSamples, uint2 Random)
{
    float E1 = frac((float)Index / NumSamples + float(Random.x) * (1.0 / 65536.0));
    float E2 = float((reversebits(Index) >> 16) ^ Random.y) * (1.0 / 65536.0);
    return float2(E1, E2);
}

// R2 准随机序列 — 各向同性蓝噪声特性
// http://extremelearning.com.au/a-simple-method-to-construct-isotropic-quasirandom-blue-noise-point-sequences/
float2 R2Sequence(uint Index)
{
    const float Phi = 1.324717957244746;
    const float2 a = float2(1.0 / Phi, 1.0 / (Phi * Phi));
    return frac(a * Index);
}

//=============================================================================
//  球面/半球/锥体采样
//=============================================================================

// 同心圆盘采样辅助函数 — 无极坐标畸变
float3 ConcentricDiskSamplingHelper(float2 E)
{
    float2 p = 2 * E - 0.99999994;
    float2 a = abs(p);
    float Lo = min(a.x, a.y);
    float Hi = max(a.x, a.y);
    float Epsilon = 5.42101086243e-20; // 2^-64，避免 0/0
    float Phi = (PI / 4) * (Lo / (Hi + Epsilon) + 2 * float(a.y >= a.x));
    float Radius = Hi;
    const uint SignMask = 0x80000000;
    float2 Disk = asfloat((asuint(float2(cos(Phi), sin(Phi))) & ~SignMask) | (asuint(p) & SignMask));
    return float3(Disk, Radius);
}

// 均匀采样单位球面, PDF = 1/(4π)
float4 UniformSampleSphere(float2 E)
{
    float Phi = 2 * PI * E.x;
    float CosTheta = 1 - 2 * E.y;
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = 1.0 / (4 * PI);
    return float4(H, PDF);
}

// 均匀采样半球, PDF = 1/(2π)
float4 UniformSampleHemisphere(float2 E)
{
    float Phi = 2 * PI * E.x;
    float CosTheta = E.y;
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = 1.0 / (2 * PI);
    return float4(H, PDF);
}

// 余弦加权半球采样, PDF = NoL/π — 漫反射重要性采样的标准方法
float4 CosineSampleHemisphere(float2 E)
{
    float Phi = 2 * PI * E.x;
    float CosTheta = sqrt(E.y);
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = CosTheta * (1.0 / PI);
    return float4(H, PDF);
}

// 同心映射版余弦半球采样 — 减少极坐标畸变
float4 CosineSampleHemisphereConcentric(float2 E)
{
    float3 Result = ConcentricDiskSamplingHelper(E);
    float SinTheta = Result.z;
    float CosTheta = sqrt(1 - SinTheta * SinTheta);
    return float4(Result.xy * SinTheta, CosTheta, CosTheta * (1.0 / PI));
}

// 均匀锥体采样 — 用于区域光、软阴影
float4 UniformSampleCone(float2 E, float CosThetaMax)
{
    float Phi = 2 * PI * E.x;
    float CosTheta = lerp(CosThetaMax, 1, E.y);
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 L;
    L.x = SinTheta * cos(Phi);
    L.y = SinTheta * sin(Phi);
    L.z = CosTheta;

    float PDF = 1.0 / (2 * PI * (1 - CosThetaMax));
    return float4(L, PDF);
}

// 数值稳定的锥体采样 — 用 SinThetaMax^2 作参数，小角度更精确
float4 UniformSampleConeRobust(float2 E, float SinThetaMax2)
{
    float Phi = 2 * PI * E.x;
    // 1-sqrt(1-x) 的级数展开，避免灾难性抵消
    float OneMinusCosThetaMax = SinThetaMax2 < 0.01
        ? SinThetaMax2 * (0.5 + 0.125 * SinThetaMax2)
        : 1 - sqrt(1 - SinThetaMax2);

    float CosTheta = 1 - OneMinusCosThetaMax * E.y;
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 L;
    L.x = SinTheta * cos(Phi);
    L.y = SinTheta * sin(Phi);
    L.z = CosTheta;
    float PDF = 1.0 / (2 * PI * OneMinusCosThetaMax);

    return float4(L, PDF);
}

// 锥体立体角
float UniformConeSolidAngle(float SinThetaMax2)
{
    float OneMinusCosThetaMax = SinThetaMax2 < 0.01
        ? SinThetaMax2 * (0.5 + 0.125 * SinThetaMax2)
        : 1 - sqrt(1 - SinThetaMax2);
    return 2 * PI * OneMinusCosThetaMax;
}

//=============================================================================
//  GGX 重要性采样
//=============================================================================

// GGX NDF 重要性采样, PDF = D * NoH / (4 * VoH)
// 返回 float4(H.xyz, PDF)
float4 ImportanceSampleGGX(float2 E, float a2)
{
    float Phi = 2 * PI * E.x;
    float CosTheta = sqrt((1 - E.y) / (1 + (a2 - 1) * E.y));
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float d = (CosTheta * a2 - CosTheta) * CosTheta + 1;
    float D = a2 / (PI * d * d);
    float PDF = D * CosTheta;

    return float4(H, PDF);
}

// VNDF 可见法线分布采样
// [Dupuy & Benyoub 2023, "Sampling Visible GGX Normals with Spherical Caps"]
// [Eto & Tokuyoshi 2023, "Bounded VNDF Sampling for Smith-GGX Reflections"]
// 比经典 GGX 采样更高效 — 只采样从 V 可见的微面法线
float4 ImportanceSampleVisibleGGX(float2 E, float2 Alpha, float3 V)
{
    // 拉伸空间
    float3 Vh = normalize(float3(Alpha * V.xy, V.z));

    // 球面帽采样
    float Phi = (2 * PI) * E.x;

    // 反射约束: 排除投影到水平面以下的方向 [Eto 2023]
    float a = saturate(min(Alpha.x, Alpha.y));
    float s = 1.0 + length(V.xy);
    float a2 = a * a;
    float s2 = s * s;
    float k = (s2 - a2 * s2) / (s2 + a2 * V.z * V.z); // Eq. 5

    float Z = lerp(1.0, -k * Vh.z, E.y);
    float SinTheta = sqrt(saturate(1 - Z * Z));
    float X = SinTheta * cos(Phi);
    float Y = SinTheta * sin(Phi);
    float3 H = float3(X, Y, Z) + Vh;

    // 反拉伸
    H = normalize(float3(Alpha * H.xy, max(0.0, H.z)));

    // 计算 PDF
    float NoV = V.z;
    float NoH = H.z;
    float VoH = dot(V, H);
    float a2Full = Alpha.x * Alpha.y;
    float3 Hs = float3(Alpha.y * H.x, Alpha.x * H.y, a2Full * NoH);
    float S2 = dot(Hs, Hs);
    float D = (1.0 / PI) * a2Full * Sq(a2Full / S2);
    float LenV = length(float3(V.x * Alpha.x, V.y * Alpha.y, NoV));
    float PDF = (2 * D * VoH) / (k * NoV + LenV);

    return float4(H, PDF);
}

//=============================================================================
//  多重重要性采样 (MIS) 权重
//  [Veach 1997, "Robust Monte Carlo Methods for Light Transport Simulation"]
//=============================================================================

// 平衡启发式 — 数值稳定版本，保证 w(a,b) + w(b,a) == 1.0
float MISWeightBalanced(float Pdf, float OtherPdf)
{
    // 使用较小/较大比值，避免溢出和 0/0
    float X = min(Pdf, OtherPdf) / max(Pdf, OtherPdf);
    float Y = Pdf == OtherPdf ? 1.0 : X; // 防御 NaN
    float M = rcp(1.0 + Y);
    return Pdf > OtherPdf ? M : 1.0 - M; // 保证交换参数后和为 1.0
}

// 幂启发式 (指数=2) — 比平衡启发式更激进地偏向高 PDF 样本
float MISWeightPower(float Pdf, float OtherPdf)
{
    float X = min(Pdf, OtherPdf) / max(Pdf, OtherPdf);
    float Y = Pdf == OtherPdf ? 1.0 : X;
    float M = rcp(1.0 + Y * Y);
    return Pdf > OtherPdf ? M : 1.0 - M;
}

// 混合 BxDF 的多波瓣 MIS 累加
void AddLobeWithMIS(inout float3 Weight, inout float Pdf, float3 LobeWeight, float LobePdf, float LobeProb)
{
    const float MinLobeProb = 1.1754943508e-38; // 最小正规浮点数
    if (LobeProb > MinLobeProb)
    {
        LobePdf *= LobeProb;
        LobeWeight *= rcp(LobeProb);
        Weight = lerp(Weight, LobeWeight, MISWeightBalanced(LobePdf, Pdf));
        Pdf += LobePdf;
    }
}

// 离散 CDF 采样后重缩放随机数到 [0,1)
float RescaleRandomNumber(float RandVal, float LowerBound, float UpperBound)
{
    const float OneMinusEpsilon = 0.99999994;
    return min((RandVal - LowerBound) / (UpperBound - LowerBound), OneMinusEpsilon);
}

// 半矢量 PDF → 反射方向 PDF 的转换
float RayPDFToReflectionRayPDF(float VoH, float RayPDF)
{
    return RayPDF / (4.0 * saturate(VoH));
}

#endif // TR_UE_MONTE_CARLO_INCLUDED
