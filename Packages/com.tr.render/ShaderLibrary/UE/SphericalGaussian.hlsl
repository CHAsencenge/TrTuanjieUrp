// 移植自 UE5 SphericalGaussian.ush
// 球面高斯 (SG) 基函数: 求值、积分、归一化、乘法、内积、卷积
// 各向异性球面高斯 (ASG) 支持
// 应用: 光照探针、间接光近似、AO 近似

#ifndef TR_UE_SPHERICAL_GAUSSIAN_INCLUDED
#define TR_UE_SPHERICAL_GAUSSIAN_INCLUDED

// G(v; u, L, a) = a * exp(L * (dot(u,v) - 1))

//=============================================================================
//  各向同性球面高斯
//=============================================================================
struct FSphericalGaussian
{
    float3 Axis;       // u — 方向轴 (归一化)
    float  Sharpness;  // L — 锐度/集中度 (λ, 越大越窄)
    float  Amplitude;  // a — 振幅
};

// 求值: G(v)
float SG_Evaluate(FSphericalGaussian G, float3 Direction)
{
    return G.Amplitude * exp(G.Sharpness * (dot(G.Axis, Direction) - 1));
}

// 球面积分: ∫G dω = 2π * a/L * (1 - e^(-2L))
float SG_Integral(FSphericalGaussian G)
{
    return (2 * PI) * G.Amplitude / G.Sharpness * (1 - exp(-2 * G.Sharpness));
}

// 归一化: G / ∫G
FSphericalGaussian SG_Normalize(FSphericalGaussian G)
{
    G.Amplitude = G.Sharpness / ((2 * PI) - (2 * PI) * exp(-2 * G.Sharpness));
    return G;
}

// 乘法: G0 × G1 → 新 SG
FSphericalGaussian SG_Mul(FSphericalGaussian G0, FSphericalGaussian G1)
{
    // um = L0*u0 + L1*u1
    float  Lm = G0.Sharpness + G1.Sharpness;
    float3 um = G0.Sharpness * G0.Axis + G1.Sharpness * G1.Axis;
    float  umLength = length(um);

    FSphericalGaussian G;
    G.Axis      = um / umLength;
    G.Sharpness = umLength;
    G.Amplitude = G0.Amplitude * G1.Amplitude * exp(umLength - Lm);
    return G;
}

// 内积: ∫G0 × G1 dω — 两个 SG 的重叠度量
float SG_Dot(FSphericalGaussian G0, FSphericalGaussian G1)
{
    float  Lm = G0.Sharpness + G1.Sharpness;
    float3 um = G0.Sharpness * G0.Axis + G1.Sharpness * G1.Axis;
    float  umLength = length(um);

    return (2 * PI) * G0.Amplitude * G1.Amplitude * exp(umLength - Lm) * (1 - exp(-2 * umLength)) / umLength;
}

// 卷积: G0 ⊛ G1
// [Iwasaki 2012, "Interactive Bi-scale Editing of Highly Glossy Materials"]
FSphericalGaussian SG_Convolve(FSphericalGaussian G0, FSphericalGaussian G1)
{
    FSphericalGaussian G;
    G.Axis      = G0.Axis;
    G.Sharpness = (G0.Sharpness * G1.Sharpness) / (G0.Sharpness + G1.Sharpness);
    G.Amplitude = (2 * PI) * (G0.Amplitude * G1.Amplitude) / (G0.Sharpness + G1.Sharpness);
    return G;
}

// von Mises-Fisher 近似: 从方向矢量 r 和值构建 SG
FSphericalGaussian SG_FromVector(float3 r, float Value)
{
    FSphericalGaussian G;

    float LengthR2 = dot(r, r);
    float InvLengthR = rsqrt(LengthR2);
    float LengthR = LengthR2 * InvLengthR;

    G.Axis      = r * InvLengthR;
    G.Sharpness = LengthR * (3 - LengthR2) / (1 - min(LengthR2, 0.9999));
    G.Amplitude = Value * G.Sharpness / ((2 * PI) - (2 * PI) * exp(-2 * G.Sharpness));

    return G;
}

// 两个 SG 的加权融合
FSphericalGaussian SG_Add(FSphericalGaussian G0, FSphericalGaussian G1)
{
    float exp2L0 = exp(-2 * G0.Sharpness);
    float exp2L1 = exp(-2 * G1.Sharpness);

    float3 r0 = ((1 + exp2L0) / (1 - exp2L0) - rcp(G0.Sharpness)) * G0.Axis;
    float3 r1 = ((1 + exp2L1) / (1 - exp2L1) - rcp(G1.Sharpness)) * G1.Axis;
    float w0 = SG_Integral(G0);
    float w1 = SG_Integral(G1);

    float3 r = (r0 * w0 + r1 * w1) / (w0 + w1);
    float w = w0 + w1;

    return SG_FromVector(r, w);
}

// 锥体半角近似: ~sqrt(2/L)
float SG_GetConeAngle(FSphericalGaussian G)
{
    return sqrt(2 / G.Sharpness);
}

//=============================================================================
//  SG 与 clamped cosine lobe 的内积
//  假设 G 已归一化，用于光照/AO 卷积
//=============================================================================
float SG_DotCosineLobe(FSphericalGaussian G, float3 N)
{
    const float muDotN = dot(G.Axis, N);

    const float c0 = 0.36;
    const float c1 = 0.25 / c0;

    float eml  = exp(-G.Sharpness);
    float em2l = eml * eml;
    float rl   = rcp(G.Sharpness);

    float scale = 1.0 + 2.0 * em2l - rl;
    float bias  = (eml - em2l) * rl - em2l;

    float x  = sqrt(1.0 - scale);
    float x0 = c0 * muDotN;
    float x1 = c1 * x;

    float n = x0 + x1;
    float y = (abs(x0) <= x1) ? n * n / x : saturate(muDotN);

    return scale * y + bias;
}

//=============================================================================
//  近似转换: 几何/AO → SG
//=============================================================================

// [Wang et al. 2009, "All-Frequency Rendering of Dynamic, Spatially-Varying Reflectance"]
// clamped cosine → SG 近似
FSphericalGaussian ClampedCosine_ToSG(float3 Normal)
{
    FSphericalGaussian G;
    G.Axis      = Normal;
    G.Sharpness = 2.133;
    G.Amplitude = 1.17;
    return G;
}

// 半球 → SG 近似
FSphericalGaussian Hemisphere_ToSG(float3 Normal)
{
    FSphericalGaussian G;
    G.Axis      = Normal;
    G.Sharpness = 0.81;
    G.Amplitude = 0.81 / (1 - exp(-2 * 0.81));
    return G;
}

// Bent Normal + AO → SG 近似
// BentNormal 需归一化，AO ∈ [0,1]，两者都是余弦加权
FSphericalGaussian BentNormalAO_ToSG(float3 BentNormal, float AO)
{
    FSphericalGaussian G;
    G.Axis = BentNormal;

    // 余弦加权球冠积分: π * sin²α
    // L ≈ 2 / acos(sqrt(1-AO))^2, 这里用无 acos 的近似
    G.Sharpness = (0.75 + 1.25 * sqrt(1 - AO)) / AO;

    // AO=1 时积分为 2π
    const float HemisphereSharpness = 0.81;
    G.Amplitude = HemisphereSharpness / (1 - exp(-2 * HemisphereSharpness));

    return G;
}

//=============================================================================
//  各向异性球面高斯 (ASG)
//=============================================================================
struct FAnisoSphericalGaussian
{
    float3 AxisX;       // 切线方向
    float3 AxisY;       // 副切线方向
    float3 AxisZ;       // 法线/主方向
    float  SharpnessX;  // 沿 X 的锐度
    float  SharpnessY;  // 沿 Y 的锐度
    float  Amplitude;   // 振幅
};

// ASG 求值
float ASG_Evaluate(FAnisoSphericalGaussian ASG, float3 Direction)
{
    float L = ASG.SharpnessX * Sq(dot(Direction, ASG.AxisX));
    float u = ASG.SharpnessY * Sq(dot(Direction, ASG.AxisY));
    return ASG.Amplitude * saturate(dot(Direction, ASG.AxisZ)) * exp(-L - u);
}

// ASG 与 SG 的内积
float ASG_DotSG(FAnisoSphericalGaussian ASG, FSphericalGaussian SG)
{
    // 将 SG 转换为 ASG 形式: ν = L/2
    float nu = SG.Sharpness * 0.5;

    ASG.Amplitude *= SG.Amplitude;
    ASG.Amplitude *= PI * rsqrt((nu + ASG.SharpnessX) * (nu + ASG.SharpnessY));
    ASG.SharpnessX = (nu * ASG.SharpnessX) / (nu + ASG.SharpnessX);
    ASG.SharpnessY = (nu * ASG.SharpnessY) / (nu + ASG.SharpnessY);

    return ASG_Evaluate(ASG, SG.Axis);
}

#endif // TR_UE_SPHERICAL_GAUSSIAN_INCLUDED
