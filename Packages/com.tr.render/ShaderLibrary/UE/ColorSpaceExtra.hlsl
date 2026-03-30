// 移植自 UE5 ColorSpace.ush
// 扩展色彩空间: CIE LAB/LCH, YCoCg 变体, 平滑 HSV

#ifndef TR_UE_COLOR_SPACE_EXTRA_INCLUDED
#define TR_UE_COLOR_SPACE_EXTRA_INCLUDED

//=============================================================================
//  CIE XYZ ↔ Linear sRGB 矩阵
//  https://en.wikipedia.org/wiki/CIE_1931_color_space
//=============================================================================

static const float3x3 UE_XYZ_2_LinearSRGB_MAT =
{
     3.2409699419, -1.5373831776, -0.4986107603,
    -0.9692436363,  1.8759675015,  0.0415550574,
     0.0556300797, -0.2039769589,  1.0569715142,
};

static const float3x3 UE_LinearSRGB_2_XYZ_MAT =
{
    0.4123907993, 0.3575843394, 0.1804807884,
    0.2126390059, 0.7151686788, 0.0721923154,
    0.0193308187, 0.1191947798, 0.9505321522,
};

float3 UE_LinearRGB_2_XYZ(float3 LinearRGB)
{
    return mul(UE_LinearSRGB_2_XYZ_MAT, LinearRGB);
}

float3 UE_XYZ_2_LinearRGB(float3 XYZ)
{
    return mul(UE_XYZ_2_LinearSRGB_MAT, XYZ);
}

//=============================================================================
//  CIE L*a*b* — 感知均匀色彩空间
//  https://en.wikipedia.org/wiki/Lab_color_space
//  假设 XYZ 在归一化范围内 (白色 RGB(1,1,1) → XYZ ≈ (0.95, 1.0, 1.09))
//=============================================================================

// D65 白点参考值 (归一化)
static const float3 UE_XYZ_WHITE_REF = float3(0.9504559271, 1.0, 1.0890577508);

// LAB 转换阈值常数
static const float UE_LAB_DELTA_SQ = 0.04280618311;  // (6/29)^2
static const float UE_LAB_DELTA_CU = 0.00885645167;  // (6/29)^3

float _lab_f(float t)
{
    // t > δ^3 时用立方根，否则用线性近似
    return (t > UE_LAB_DELTA_CU)
        ? pow(max(t, UE_LAB_DELTA_CU), 1.0 / 3.0)
        : (t / (3.0 * UE_LAB_DELTA_SQ)) + 4.0 / 29.0;
}

float _lab_f_inv(float t)
{
    float t3 = t * t * t;
    return (t3 > UE_LAB_DELTA_CU)
        ? t3
        : (3.0 * UE_LAB_DELTA_SQ) * (t - 4.0 / 29.0);
}

// Linear RGB → CIE L*a*b*
// L: 明度 [0, 100], a/b: 色度 (无固定范围，典型 ±128)
float3 LinearRGB_2_LAB(float3 LinearRGB)
{
    float3 XYZ = UE_LinearRGB_2_XYZ(LinearRGB);

    float f_X = _lab_f(XYZ.x / UE_XYZ_WHITE_REF.x);
    float f_Y = _lab_f(XYZ.y / UE_XYZ_WHITE_REF.y);
    float f_Z = _lab_f(XYZ.z / UE_XYZ_WHITE_REF.z);

    float L = 116.0 * f_Y - 16.0;
    float a = 500.0 * (f_X - f_Y);
    float b = 200.0 * (f_Y - f_Z);

    return float3(L, a, b);
}

// CIE L*a*b* → Linear RGB
float3 LAB_2_LinearRGB(float3 LAB)
{
    float t_y = (LAB.x + 16.0) / 116.0;
    float t_x = t_y + (LAB.y / 500.0);
    float t_z = t_y - (LAB.z / 200.0);

    float X = UE_XYZ_WHITE_REF.x * _lab_f_inv(t_x);
    float Y = UE_XYZ_WHITE_REF.y * _lab_f_inv(t_y);
    float Z = UE_XYZ_WHITE_REF.z * _lab_f_inv(t_z);

    return UE_XYZ_2_LinearRGB(float3(X, Y, Z));
}

//=============================================================================
//  CIE LCH — LAB 的圆柱坐标形式
//  L: 明度, C: 彩度 (饱和度), H: 色相角 (度)
//=============================================================================
float3 LAB_2_LCH(float3 LAB)
{
    float3 LCH;
    LCH.x = LAB.x;
    LCH.y = length(LAB.yz);
    float HInDegree = 0.0;

    if (LAB.z != 0 || LAB.y != 0)
    {
        HInDegree = atan2(LAB.z, LAB.y) * 180.0 / PI;
        HInDegree += lerp(0, 360.0, HInDegree < 0);
    }
    LCH.z = HInDegree;
    return LCH;
}

//=============================================================================
//  YCoCg 色彩空间 — 亮度/色度正交分离，适合颜色压缩
//=============================================================================

// 亮度乘数 (ALU 优化)
#define UE_YCOCG_LUMA_MULTIPLIER 4.0

// Linear RGB → YCoCg (Y∈[0,4], Co/Cg∈[-2,2])
float3 UE_LinearRGB_2_YCoCg(float3 RGB)
{
    float Y  = dot(RGB, float3(1, 2, 1));
    float Co = dot(RGB, float3(2, 0, -2));
    float Cg = dot(RGB, float3(-1, 2, -1));
    return float3(Y, Co, Cg);
}

// YCoCg → Linear RGB
float3 UE_YCoCg_2_LinearRGB(float3 YCoCg)
{
    float Y  = YCoCg.x * 0.25;
    float Co = YCoCg.y * 0.25;
    float Cg = YCoCg.z * 0.25;
    return float3(Y + Co - Cg, Y + Cg, Y - Co - Cg);
}

// YCoCg → LCoCg (亮度归一化色度)
float3 UE_YCoCg_2_LCoCg(float3 YCoCg)
{
    return float3(YCoCg.x, YCoCg.yz * (YCoCg.x > 0 ? rcp(YCoCg.x) : 0));
}

float3 UE_LCoCg_2_YCoCg(float3 LCoCg)
{
    return float3(LCoCg.x, LCoCg.x * LCoCg.yz);
}

// 直接转换
float3 UE_LinearRGB_2_LCoCg(float3 RGB) { return UE_YCoCg_2_LCoCg(UE_LinearRGB_2_YCoCg(RGB)); }
float3 UE_LCoCg_2_LinearRGB(float3 LCoCg) { return UE_YCoCg_2_LinearRGB(UE_LCoCg_2_YCoCg(LCoCg)); }

// 归一化 YCoCg: 所有分量映射到 [0,1]，适合存入纹理
float3 UE_LinearRGB_2_NormalisedYCoCg(float3 RGB)
{
    return UE_LinearRGB_2_YCoCg(RGB) * float3(1.0 / UE_YCOCG_LUMA_MULTIPLIER, 0.25, 0.25) + float3(0.0, 0.5, 0.5);
}

float3 UE_NormalisedYCoCg_2_LinearRGB(float3 YCoCg)
{
    return UE_YCoCg_2_LinearRGB(YCoCg * float3(UE_YCOCG_LUMA_MULTIPLIER, 4.0, 4.0) + float3(0.0, -2.0, -2.0));
}

//=============================================================================
//  HSV 工具
//=============================================================================

// HUE → Linear RGB (色相轮)
float3 UE_HUE_2_LinearRGB(float H)
{
    float R = abs(H * 6 - 3) - 1;
    float G = 2 - abs(H * 6 - 2);
    float B = 2 - abs(H * 6 - 4);
    return saturate(float3(R, G, B));
}

// HSV → Linear RGB
float3 UE_HSV_2_LinearRGB(float3 HSV)
{
    float3 RGB = UE_HUE_2_LinearRGB(HSV.x);
    return ((RGB - 1) * HSV.y + 1) * HSV.z;
}

// Linear RGB → HSV
float3 UE_LinearRGB_2_HSV(float3 RGB)
{
    float4 P = (RGB.g < RGB.b) ? float4(RGB.bg, -1.0, 2.0 / 3.0) : float4(RGB.gb, 0.0, -1.0 / 3.0);
    float4 Q = (RGB.r < P.x) ? float4(P.xyw, RGB.r) : float4(RGB.r, P.yzx);
    float Chroma = Q.x - min(Q.w, Q.y);
    float Hue = abs((Q.w - Q.y) / (6.0 * Chroma + 1e-10) + Q.z);
    float s = Chroma / (Q.x + 1e-10);
    return float3(Hue, s, Q.x);
}

// 三次平滑 HSV → Linear RGB [Quilez, Shadertoy]
// 比标准 HSV 转换更平滑，减少色带
float3 HSV_2_LinearRGB_Smooth(float3 HSV)
{
    float3 RGB = clamp(abs(fmod(HSV.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    RGB = RGB * RGB * (3.0 - 2.0 * RGB); // 三次 Hermite 平滑
    return HSV.z * lerp(float3(1.0, 1.0, 1.0), RGB, HSV.y);
}

//=============================================================================
//  LMS 色彩空间 (色觉适应)
//=============================================================================

static const float3x3 UE_sRGB_2_LMS_MAT =
{
    17.8824,  43.5161,  4.1193,
     3.4557,  27.1554,  3.8671,
     0.02996,  0.18431, 1.4670,
};

static const float3x3 UE_LMS_2_sRGB_MAT =
{
    0.0809,  -0.1305,   0.1167,
   -0.0102,   0.0540,  -0.1136,
   -0.0003,  -0.0041,   0.6935,
};

float3 UE_sRGB_2_LMS(float3 RGB)  { return mul(UE_sRGB_2_LMS_MAT, RGB); }
float3 UE_LMS_2_sRGB(float3 LMS)  { return mul(UE_LMS_2_sRGB_MAT, LMS); }

#endif // TR_UE_COLOR_SPACE_EXTRA_INCLUDED
