// 移植自 UE5 TextureSampling.ush
// 高质量纹理采样: Bicubic Catmull-Rom 5-tap 优化

#ifndef TR_UE_TEXTURE_SAMPLING_EXTRA_INCLUDED
#define TR_UE_TEXTURE_SAMPLING_EXTRA_INCLUDED

//=============================================================================
//  Bicubic2DCatmullRom — Catmull-Rom 双三次权重计算
//  将 4-tap 双三次采样优化为 3 对加权坐标:
//  利用双线性硬件在相邻像素对间插值，减少到 5 次纹理采样
//
//  输出:
//    Sample[3] — 3 个采样 UV 坐标
//    Weight[3] — 对应权重
//=============================================================================
void Bicubic2DCatmullRom(in float2 UV, in float2 Size, in float2 InvSize,
    out float2 Sample[3], out half2 Weight[3])
{
    UV *= Size;

    float2 tc = floor(UV - 0.5) + 0.5;
    half2 f = half2(UV - tc);
    half2 f2 = f * f;
    half2 f3 = f2 * f;

    // Catmull-Rom 基函数权重
    half2 w0 = f2 - 0.5 * (f3 + f);
    half2 w1 = 1.5 * f3 - 2.5 * f2 + 1;
    half2 w3 = 0.5 * (f3 - f2);
    half2 w2 = 1 - w0 - w1 - w3;

    Weight[0] = w0;
    Weight[1] = w1 + w2;            // 合并中间两个权重
    Weight[2] = w3;

    Sample[0] = tc - 1;
    Sample[1] = tc + w2 * rcp(Weight[1]); // 利用双线性在 w1/w2 间插值
    Sample[2] = tc + 2;

    // 像素坐标 → UV 坐标
    Sample[0] *= InvSize;
    Sample[1] *= InvSize;
    Sample[2] *= InvSize;
}

//=============================================================================
//  FCatmullRomSamples — 5-tap 优化双三次采样结构
//  省略四角样本 (贡献极小)，仅保留十字形 5 个采样点
//  FinalMultiplier 用于补偿省略的角样本权重
//=============================================================================

#define BICUBIC_CATMULL_ROM_SAMPLES 5

struct FCatmullRomSamples
{
    uint  Count;                                    // 固定 = 5
    int2  UVDir[BICUBIC_CATMULL_ROM_SAMPLES];       // 相对主 UV 的方向
    float2 UV[BICUBIC_CATMULL_ROM_SAMPLES];          // 双线性采样 UV
    half  Weight[BICUBIC_CATMULL_ROM_SAMPLES];       // 采样权重
    float FinalMultiplier;                           // 归一化乘数
};

// 计算 5 个优化采样点
FCatmullRomSamples GetBicubic2DCatmullRomSamples(float2 UV, float2 Size, in float2 InvSize)
{
    FCatmullRomSamples Samples;
    Samples.Count = BICUBIC_CATMULL_ROM_SAMPLES;

    half2 Weight[3];
    float2 Sample[3];
    Bicubic2DCatmullRom(UV, Size, InvSize, Sample, Weight);

    // 十字形 5 采样点: 上、左、中、右、下
    Samples.UV[0] = float2(Sample[1].x, Sample[0].y); // 上
    Samples.UV[1] = float2(Sample[0].x, Sample[1].y); // 左
    Samples.UV[2] = float2(Sample[1].x, Sample[1].y); // 中
    Samples.UV[3] = float2(Sample[2].x, Sample[1].y); // 右
    Samples.UV[4] = float2(Sample[1].x, Sample[2].y); // 下

    Samples.Weight[0] = Weight[1].x * Weight[0].y;
    Samples.Weight[1] = Weight[0].x * Weight[1].y;
    Samples.Weight[2] = Weight[1].x * Weight[1].y;
    Samples.Weight[3] = Weight[2].x * Weight[1].y;
    Samples.Weight[4] = Weight[1].x * Weight[2].y;

    Samples.UVDir[0] = int2( 0, -1);
    Samples.UVDir[1] = int2(-1,  0);
    Samples.UVDir[2] = int2( 0,  0);
    Samples.UVDir[3] = int2( 1,  0);
    Samples.UVDir[4] = int2( 0,  1);

    // 重新加权: 补偿被省略的四角样本
    float CornerWeights;
    CornerWeights  = Samples.Weight[0];
    CornerWeights += Samples.Weight[1];
    CornerWeights += Samples.Weight[2];
    CornerWeights += Samples.Weight[3];
    CornerWeights += Samples.Weight[4];
    Samples.FinalMultiplier = 1 / CornerWeights;

    return Samples;
}

// 完整的双三次纹理采样 — 5 次 SampleLevel + 加权求和
// 用法: float4 color = Texture2DSampleBicubic(MyTex, MySampler, uv, texSize, texInvSize);
float4 Texture2DSampleBicubic(Texture2D Tex, SamplerState Sampler, float2 UV, float2 Size, float2 InvSize)
{
    FCatmullRomSamples Samples = GetBicubic2DCatmullRomSamples(UV, Size, InvSize);

    float4 OutColor = 0;
    for (uint i = 0; i < Samples.Count; i++)
    {
        OutColor += Tex.SampleLevel(Sampler, Samples.UV[i], 0) * Samples.Weight[i];
    }
    OutColor *= Samples.FinalMultiplier;

    return OutColor;
}

#endif // TR_UE_TEXTURE_SAMPLING_EXTRA_INCLUDED
