// 移植自 UE5 TonemapCommon.ush
// 色调映射: UE5 FilmToneMap, Hable (Uncharted 2), Reinhard
// 白平衡: 色温/色调 → 色度适应矩阵

#ifndef TR_UE_TONEMAP_EXTRA_INCLUDED
#define TR_UE_TONEMAP_EXTRA_INCLUDED

//=============================================================================
//  FilmToneMap — UE5 标志性 S 曲线色调映射
//  参数化的 toe/shoulder/slope，可精确控制暗部和亮部压缩
//  输入: 线性 HDR 颜色 (AP1 色彩空间)
//  输出: [0,1] 色调映射结果
//
//  参数说明 (通过函数参数传入):
//    Slope      — 中间段斜率 (典型 0.63-0.98)
//    Toe        — 暗部曲率 (典型 0.3-0.63)
//    Shoulder   — 亮部曲率 (典型 0.22-0.47)
//    BlackClip  — 纯黑扩展 (典型 0)
//    WhiteClip  — 纯白扩展 (典型 0-0.035)
//=============================================================================
half3 FilmToneMap(half3 WorkingColor, float Slope, float Toe, float Shoulder, float BlackClip, float WhiteClip)
{
    WorkingColor = max(0, WorkingColor);

    // 预去饱和: 略微降低饱和度，避免 ACES 风格过饱和
    float WorkingLuma = dot(WorkingColor, float3(0.2722287168, 0.6740817658, 0.0536895174)); // AP1 亮度
    WorkingColor = lerp(WorkingLuma, WorkingColor, 0.96);

    const half ToeScale      = 1 + BlackClip - Toe;
    const half ShoulderScale = 1 + WhiteClip - Shoulder;

    const float InMatch  = 0.18;
    const float OutMatch = 0.18;

    float ToeMatch;
    if (Toe > 0.8)
    {
        // 0.18 在直线段上
        ToeMatch = (1 - Toe - OutMatch) / Slope + log10(InMatch);
    }
    else
    {
        // 0.18 在 toe 段上
        const float bt = (OutMatch + BlackClip) / ToeScale - 1;
        ToeMatch = log10(InMatch) - 0.5 * log((1 + bt) / (1 - bt)) * (ToeScale / Slope);
    }

    float StraightMatch  = (1 - Toe) / Slope - ToeMatch;
    float ShoulderMatch  = Shoulder / Slope - StraightMatch;

    half3 LogColor       = log10(WorkingColor);
    half3 StraightColor  = Slope * (LogColor + StraightMatch);

    half3 ToeColor       = (-BlackClip) + (2 * ToeScale) / (1 + exp((-2 * Slope / ToeScale) * (LogColor - ToeMatch)));
    half3 ShoulderColor  = (1 + WhiteClip) - (2 * ShoulderScale) / (1 + exp((2 * Slope / ShoulderScale) * (LogColor - ShoulderMatch)));

    ToeColor      = LogColor < ToeMatch      ? ToeColor      : StraightColor;
    ShoulderColor = LogColor > ShoulderMatch  ? ShoulderColor : StraightColor;

    half3 t = saturate((LogColor - ToeMatch) / (ShoulderMatch - ToeMatch));
    t = ShoulderMatch < ToeMatch ? 1 - t : t;
    t = (3 - 2 * t) * t * t; // Hermite 平滑
    half3 ToneColor = lerp(ToeColor, ShoulderColor, t);

    // 后去饱和
    ToneColor = lerp(dot(float3(ToneColor), float3(0.2722287168, 0.6740817658, 0.0536895174)), ToneColor, 0.93);

    return max(0, ToneColor);
}

// 使用 UE5 默认 ACES 参数的便捷重载
half3 FilmToneMapDefault(half3 WorkingColor)
{
    return FilmToneMap(WorkingColor, 0.91, 0.53, 0.23, 0.0, 0.035);
}

//=============================================================================
//  Hable ToneMap — "Uncharted 2" 曲线
//  John Hable 的经典色调映射，简单高效
//=============================================================================

float3 HableToneMapCurve(float3 X)
{
    const float A = 0.15; // Shoulder Strength
    const float B = 0.50; // Linear Strength
    const float C = 0.10; // Linear Angle
    const float D = 0.20; // Toe Strength
    const float E = 0.02; // Toe Numerator
    const float F = 0.30; // Toe Denominator

    return ((X * (A * X + C * B) + D * E) / (X * (A * X + B) + D * F)) - E / F;
}

float3 HableToneMap(float3 LinearColor)
{
    LinearColor = max(0, LinearColor);

    const float3 W = 11.2;                         // 白点
    const float3 WhiteScale = 1.0 / HableToneMapCurve(W);
    const float ExposureBias = 2.0;

    return HableToneMapCurve(LinearColor * ExposureBias) * WhiteScale;
}

//=============================================================================
//  Simple Reinhard — 最简色调映射 c/(1+c)
//=============================================================================
float3 SimpleReinhardToneMap(float3 LinearColor)
{
    return LinearColor / (1.0 + LinearColor);
}

//=============================================================================
//  白平衡 — 色温/色调转换
//  基于 Planckian 轨迹和 CIE D 光源色度
//=============================================================================

// Planckian 轨迹色度 — 对 1000K~15000K 精确
// [Krystek 1985, "An algorithm to calculate correlated colour temperature"]
float2 PlanckianLocusChromaticity(float Temp)
{
    float u = (0.860117757 + 1.54118254e-4 * Temp + 1.28641212e-7 * Temp * Temp)
            / (1.0 + 8.42420235e-4 * Temp + 7.08145163e-7 * Temp * Temp);
    float v = (0.317398726 + 4.22806245e-5 * Temp + 4.20481691e-8 * Temp * Temp)
            / (1.0 - 2.89741816e-5 * Temp + 1.61456053e-7 * Temp * Temp);

    float x = 3 * u / (2 * u - 8 * v + 4);
    float y = 2 * v / (2 * u - 8 * v + 4);
    return float2(x, y);
}

// CIE D 光源色度 — 对 4000K~25000K 精确
float2 D_IlluminantChromaticity(float Temp)
{
    Temp *= 1.4388 / 1.438; // Planck 定律修正
    float OneOverTemp = 1.0 / Temp;
    float x = Temp <= 7000
        ? 0.244063 + (0.09911e3 + (2.9678e6 - 4.6070e9 * OneOverTemp) * OneOverTemp) * OneOverTemp
        : 0.237040 + (0.24748e3 + (1.9018e6 - 2.0064e9 * OneOverTemp) * OneOverTemp) * OneOverTemp;
    float y = -3 * x * x + 2.87 * x - 0.275;
    return float2(x, y);
}

// 从色度坐标反推相关色温
// [McCamy 1992]
float CorrelatedColorTemperature(float x, float y)
{
    float n = (x - 0.3320) / (y - 0.1858);
    return -449 * n * n * n + 3525 * n * n - 6823.3 * n + 5520.33;
}

// Planckian 等温线 — 在色温点沿垂直方向偏移 (色调/Tint 控制)
float2 PlanckianIsothermal(float Temp, float Tint)
{
    float u = (0.860117757 + 1.54118254e-4 * Temp + 1.28641212e-7 * Temp * Temp)
            / (1.0 + 8.42420235e-4 * Temp + 7.08145163e-7 * Temp * Temp);
    float v = (0.317398726 + 4.22806245e-5 * Temp + 4.20481691e-8 * Temp * Temp)
            / (1.0 - 2.89741816e-5 * Temp + 1.61456053e-7 * Temp * Temp);

    float ud = (-1.13758118e9 - 1.91615621e6 * Temp - 1.53177 * Temp * Temp)
             / Sq(1.41213984e6 + 1189.62 * Temp + Temp * Temp);
    float vd = (1.97471536e9 - 705674.0 * Temp - 308.607 * Temp * Temp)
             / Sq(6.19363586e6 - 179.456 * Temp + Temp * Temp);

    float2 uvd = normalize(float2(ud, vd));

    // 相关色温在 ±0.05 范围内有意义
    u +=  uvd.y * Tint * 0.05;
    v += -uvd.x * Tint * 0.05;

    float x = 3 * u / (2 * u - 8 * v + 4);
    float y = 2 * v / (2 * u - 8 * v + 4);
    return float2(x, y);
}

// 白平衡校正 — 从源色温/色调计算色度适应矩阵并应用
// 需要传入工作色彩空间 ↔ XYZ 的转换矩阵
// WCS = Working Color Space
float3 WhiteBalance(float3 LinearColor, float WhiteTemp, float WhiteTint,
    const float3x3 WCS_2_XYZ, const float3x3 XYZ_2_WCS)
{
    float2 SrcWhiteDaylight  = D_IlluminantChromaticity(WhiteTemp);
    float2 SrcWhitePlankian  = PlanckianLocusChromaticity(WhiteTemp);
    float2 SrcWhite = WhiteTemp < 4000 ? SrcWhitePlankian : SrcWhiteDaylight;
    float2 D65White = float2(0.31270, 0.32900);

    // 沿等温线偏移 (Tint)
    float2 Isothermal = PlanckianIsothermal(WhiteTemp, WhiteTint) - SrcWhitePlankian;
    SrcWhite += Isothermal;

    // Bradford 色度适应矩阵
    // 从源白点适应到 D65
    // ChromaticAdaptation 在此内联实现
    float3 Src_XYZ = float3(SrcWhite.x / SrcWhite.y, 1.0, (1.0 - SrcWhite.x - SrcWhite.y) / SrcWhite.y);
    float3 Dst_XYZ = float3(D65White.x / D65White.y, 1.0, (1.0 - D65White.x - D65White.y) / D65White.y);

    // Bradford 矩阵
    static const float3x3 Bradford =
    {
         0.8951,  0.2664, -0.1614,
        -0.7502,  1.7135,  0.0367,
         0.0389, -0.0685,  1.0296,
    };
    static const float3x3 BradfordInv =
    {
         0.9869929, -0.1470543,  0.1599627,
         0.4323053,  0.5183603,  0.0492912,
        -0.0085287,  0.0400428,  0.9684867,
    };

    float3 Src_LMS = mul(Bradford, Src_XYZ);
    float3 Dst_LMS = mul(Bradford, Dst_XYZ);
    float3 Scale = Dst_LMS / Src_LMS;

    float3x3 CAT = mul(BradfordInv, float3x3(
        Scale.x, 0, 0,
        0, Scale.y, 0,
        0, 0, Scale.z
    ));
    CAT = mul(CAT, Bradford);

    // 完整变换: WCS → XYZ → 适应 → XYZ → WCS
    float3x3 WhiteBalanceMat = mul(XYZ_2_WCS, mul(CAT, WCS_2_XYZ));

    return mul(WhiteBalanceMat, LinearColor);
}

// 便捷版本: 假设工作色彩空间为 sRGB
float3 WhiteBalanceSRGB(float3 LinearColor, float WhiteTemp, float WhiteTint)
{
    static const float3x3 sRGB_2_XYZ =
    {
        0.4123907993, 0.3575843394, 0.1804807884,
        0.2126390059, 0.7151686788, 0.0721923154,
        0.0193308187, 0.1191947798, 0.9505321522,
    };
    static const float3x3 XYZ_2_sRGB =
    {
         3.2409699419, -1.5373831776, -0.4986107603,
        -0.9692436363,  1.8759675015,  0.0415550574,
         0.0556300797, -0.2039769589,  1.0569715142,
    };
    return WhiteBalance(LinearColor, WhiteTemp, WhiteTint, sRGB_2_XYZ, XYZ_2_sRGB);
}

#endif // TR_UE_TONEMAP_EXTRA_INCLUDED
