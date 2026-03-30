// 移植自 UE5 Random.ush 噪声部分 (仅 ALU 版本，无纹理依赖)
// 程序化噪声: Perlin 梯度噪声、Simplex + Jacobian、Voronoi

#ifndef TR_UE_NOISE_INCLUDED
#define TR_UE_NOISE_INCLUDED

#include "Packages/com.tr.render/ShaderLibrary/UE/RandomPCG.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/UE/Hash.hlsl"

//=============================================================================
//  内部工具函数
//=============================================================================

// 平铺坐标包裹
float3 NoiseTileWrap(float3 v, bool bTiling, float RepeatSize)
{
    return bTiling ? (frac(v / RepeatSize) * RepeatSize) : v;
}

// Perlin 平滑多项式: 6t^5 - 15t^4 + 10t^3 (C2 连续)
float4 PerlinRamp(float4 t)
{
    return t * t * t * (t * (t * 6 - 15) + 10);
}

// Perlin 平滑多项式的解析导数
float4 PerlinRampDerivative(float4 t)
{
    return t * t * (t * (t * 30 - 60) + 30);
}

// 修正噪声梯度项
#define MGRADIENT_MASK int3(0x8000, 0x4000, 0x2000)
#define MGRADIENT_SCALE float3(1.0 / 0x4000, 1.0 / 0x2000, 1.0 / 0x1000)

float4 MGradient(int seed, float3 offset)
{
    uint rand = Rand3DPCG16(int3(seed, 0, 0)).x;
    float3 direction = float3(rand.xxx & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    return float4(direction, dot(direction, offset));
}

// Blum-Blum-Shub 伪随机数 (用于值噪声)
#define BBS_PRIME24 4093

float RandBBSfloat(float seed)
{
    float s = frac(seed / BBS_PRIME24);
    s = frac(s * s * BBS_PRIME24);
    s = frac(s * s * BBS_PRIME24);
    return s;
}

// 计算 Perlin 噪声八角种子值
float3 NoiseSeeds(float3 v, bool bTiling, float RepeatSize,
    out float seed000, out float seed001, out float seed010, out float seed011,
    out float seed100, out float seed101, out float seed110, out float seed111)
{
    float3 fv = frac(v);
    float3 iv = floor(v);
    const float3 primes = float3(19, 47, 101);

    if (bTiling)
    {
        seed000 = dot(primes, NoiseTileWrap(iv, true, RepeatSize));
        seed100 = dot(primes, NoiseTileWrap(iv + float3(1, 0, 0), true, RepeatSize));
        seed010 = dot(primes, NoiseTileWrap(iv + float3(0, 1, 0), true, RepeatSize));
        seed110 = dot(primes, NoiseTileWrap(iv + float3(1, 1, 0), true, RepeatSize));
        seed001 = dot(primes, NoiseTileWrap(iv + float3(0, 0, 1), true, RepeatSize));
        seed101 = dot(primes, NoiseTileWrap(iv + float3(1, 0, 1), true, RepeatSize));
        seed011 = dot(primes, NoiseTileWrap(iv + float3(0, 1, 1), true, RepeatSize));
        seed111 = dot(primes, NoiseTileWrap(iv + float3(1, 1, 1), true, RepeatSize));
    }
    else
    {
        seed000 = dot(iv, primes);
        seed100 = seed000 + primes.x;
        seed010 = seed000 + primes.y;
        seed110 = seed100 + primes.y;
        seed001 = seed000 + primes.z;
        seed101 = seed100 + primes.z;
        seed011 = seed010 + primes.z;
        seed111 = seed110 + primes.z;
    }
    return fv;
}

//=============================================================================
//  GradientNoise3D_ALU — 纯 ALU 梯度 (Perlin) 噪声
//  @param v          3D 噪声坐标，2D 用 float3(x,y,0)
//  @param bTiling    是否平铺
//  @param RepeatSize 平铺尺寸
//  @return           [-1, 1] 范围的随机值
//=============================================================================
float GradientNoise3D_ALU(float3 v, bool bTiling, float RepeatSize)
{
    float seed000, seed001, seed010, seed011, seed100, seed101, seed110, seed111;
    float3 fv = NoiseSeeds(v, bTiling, RepeatSize,
        seed000, seed001, seed010, seed011, seed100, seed101, seed110, seed111);

    float rand000 = MGradient(int(seed000), fv - float3(0, 0, 0)).w;
    float rand100 = MGradient(int(seed100), fv - float3(1, 0, 0)).w;
    float rand010 = MGradient(int(seed010), fv - float3(0, 1, 0)).w;
    float rand110 = MGradient(int(seed110), fv - float3(1, 1, 0)).w;
    float rand001 = MGradient(int(seed001), fv - float3(0, 0, 1)).w;
    float rand101 = MGradient(int(seed101), fv - float3(1, 0, 1)).w;
    float rand011 = MGradient(int(seed011), fv - float3(0, 1, 1)).w;
    float rand111 = MGradient(int(seed111), fv - float3(1, 1, 1)).w;

    float3 Weights = PerlinRamp(float4(fv, 0)).xyz;

    float i = lerp(lerp(rand000, rand100, Weights.x), lerp(rand010, rand110, Weights.x), Weights.y);
    float j = lerp(lerp(rand001, rand101, Weights.x), lerp(rand011, rand111, Weights.x), Weights.y);
    return lerp(i, j, Weights.z);
}

// 3D 值噪声 — 用 BBS 伪随机生成格点值后三线性插值
float ValueNoise3D_ALU(float3 v, bool bTiling, float RepeatSize)
{
    float seed000, seed001, seed010, seed011, seed100, seed101, seed110, seed111;
    float3 fv = NoiseSeeds(v, bTiling, RepeatSize,
        seed000, seed001, seed010, seed011, seed100, seed101, seed110, seed111);

    float rand000 = RandBBSfloat(seed000) * 2 - 1;
    float rand100 = RandBBSfloat(seed100) * 2 - 1;
    float rand010 = RandBBSfloat(seed010) * 2 - 1;
    float rand110 = RandBBSfloat(seed110) * 2 - 1;
    float rand001 = RandBBSfloat(seed001) * 2 - 1;
    float rand101 = RandBBSfloat(seed101) * 2 - 1;
    float rand011 = RandBBSfloat(seed011) * 2 - 1;
    float rand111 = RandBBSfloat(seed111) * 2 - 1;

    float3 Weights = PerlinRamp(float4(fv, 0)).xyz;

    float i = lerp(lerp(rand000, rand100, Weights.x), lerp(rand010, rand110, Weights.x), Weights.y);
    float j = lerp(lerp(rand001, rand101, Weights.x), lerp(rand011, rand111, Weights.x), Weights.y);
    return lerp(i, j, Weights.z);
}

//=============================================================================
//  JacobianSimplex_ALU — Simplex 噪声 + 雅可比矩阵
//  返回 float3x4: J[i].xyz = 梯度, J[i].w = 噪声值
//  可从中提取: 噪声值、梯度、旋度、散度
//  用法示例:
//    float3x4 J = JacobianSimplex_ALU(v, false, 0);
//    float3 noise = float3(J[0].w, J[1].w, J[2].w);
//    float3 curl  = float3(J[1][2]-J[2][1], J[2][0]-J[0][2], J[0][1]-J[1][0]);
//=============================================================================

// Simplex 四面体角点 [McEwan et al. 2011]
float4x3 SimplexCorners(float3 v)
{
    float3 tet = floor(v + v.x / 3 + v.y / 3 + v.z / 3);
    float3 base = tet - tet.x / 6 - tet.y / 6 - tet.z / 6;
    float3 f = v - base;

    float3 g = step(f.yzx, f.xyz), h = 1 - g.zxy;
    float3 a1 = min(g, h) - 1.0 / 6.0, a2 = max(g, h) - 1.0 / 3.0;

    return float4x3(base, base + a1, base + a2, base + 0.5);
}

// 改进 Simplex 平滑权重
float4 SimplexSmooth(float4x3 f)
{
    const float scale = 1024.0 / 375.0; // 缩放到 [-1,1]
    float4 d = float4(dot(f[0], f[0]), dot(f[1], f[1]), dot(f[2], f[2]), dot(f[3], f[3]));
    float4 s = saturate(2 * d);
    return (1 * scale + s * (-3 * scale + s * (3 * scale - s * scale)));
}

// Simplex 平滑权重的导数
float3x4 SimplexDSmooth(float4x3 f)
{
    const float scale = 1024.0 / 375.0;
    float4 d = float4(dot(f[0], f[0]), dot(f[1], f[1]), dot(f[2], f[2]), dot(f[3], f[3]));
    float4 s = saturate(2 * d);
    s = -12 * scale + s * (24 * scale - s * 12 * scale);

    return float3x4(
        s * float4(f[0][0], f[1][0], f[2][0], f[3][0]),
        s * float4(f[0][1], f[1][1], f[2][1], f[3][1]),
        s * float4(f[0][2], f[1][2], f[2][2], f[3][2]));
}

float3x4 JacobianSimplex_ALU(float3 v, bool bTiling, float RepeatSize)
{
    float4x3 T = SimplexCorners(v);
    uint3 rand;
    float4x3 gvec[3], fv;
    float3x4 grad;

    // 处理四面体的 4 个顶点
    fv[0] = v - T[0];
    rand = Rand3DPCG16(int3(floor(NoiseTileWrap(6 * T[0] + 0.5, bTiling, RepeatSize))));
    gvec[0][0] = float3(rand.xxx & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[1][0] = float3(rand.yyy & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[2][0] = float3(rand.zzz & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    grad[0][0] = dot(gvec[0][0], fv[0]); grad[1][0] = dot(gvec[1][0], fv[0]); grad[2][0] = dot(gvec[2][0], fv[0]);

    fv[1] = v - T[1];
    rand = Rand3DPCG16(int3(floor(NoiseTileWrap(6 * T[1] + 0.5, bTiling, RepeatSize))));
    gvec[0][1] = float3(rand.xxx & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[1][1] = float3(rand.yyy & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[2][1] = float3(rand.zzz & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    grad[0][1] = dot(gvec[0][1], fv[1]); grad[1][1] = dot(gvec[1][1], fv[1]); grad[2][1] = dot(gvec[2][1], fv[1]);

    fv[2] = v - T[2];
    rand = Rand3DPCG16(int3(floor(NoiseTileWrap(6 * T[2] + 0.5, bTiling, RepeatSize))));
    gvec[0][2] = float3(rand.xxx & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[1][2] = float3(rand.yyy & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[2][2] = float3(rand.zzz & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    grad[0][2] = dot(gvec[0][2], fv[2]); grad[1][2] = dot(gvec[1][2], fv[2]); grad[2][2] = dot(gvec[2][2], fv[2]);

    fv[3] = v - T[3];
    rand = Rand3DPCG16(int3(floor(NoiseTileWrap(6 * T[3] + 0.5, bTiling, RepeatSize))));
    gvec[0][3] = float3(rand.xxx & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[1][3] = float3(rand.yyy & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    gvec[2][3] = float3(rand.zzz & MGRADIENT_MASK) * MGRADIENT_SCALE - 1;
    grad[0][3] = dot(gvec[0][3], fv[3]); grad[1][3] = dot(gvec[1][3], fv[3]); grad[2][3] = dot(gvec[2][3], fv[3]);

    // 混合梯度
    float4 sv = SimplexSmooth(fv);
    float3x4 ds = SimplexDSmooth(fv);

    float3x4 jacobian;
    jacobian[0] = float4(mul(sv, gvec[0]) + mul(ds, grad[0]), dot(sv, grad[0]));
    jacobian[1] = float4(mul(sv, gvec[1]) + mul(ds, grad[1]), dot(sv, grad[1]));
    jacobian[2] = float4(mul(sv, gvec[2]) + mul(ds, grad[2]), dot(sv, grad[2]));

    return jacobian;
}

//=============================================================================
//  VoronoiNoise3D_ALU — 多质量等级 Voronoi 噪声
//  Quality 1-2: 2×2×2 搜索,  Quality 3: 3×3×3,  Quality 4: 4×4×4
//  @param bDistanceOnly 为 true 时仅返回距离(.w)，跳过位置计算
//  @return float4(最近种子点位置.xyz, 距离.w)
//=============================================================================

float3 VoronoiCornerSample(float3 pos, int Quality)
{
    // 随机偏移 [-0.5, 0.5]
    float3 noise = float3(Rand3DPCG16(int3(pos))) / 0xffff - 0.5;

    // Quality 1-2: 球面分布，保证在 2×2×2 内找到
    if (Quality <= 2)
        return normalize(noise) * 0.2588;

    // Quality 3: 球面分布，3×3×3 搜索
    if (Quality == 3)
        return normalize(noise) * 0.3090;

    // Quality 4: 完全随机抖动
    return noise;
}

float4 VoronoiCompare(float4 minval, float3 candidate, float3 offset, bool bDistanceOnly)
{
    if (bDistanceOnly)
    {
        return float4(0, 0, 0, min(minval.w, dot(offset, offset)));
    }
    else
    {
        float newdist = dot(offset, offset);
        return newdist > minval.w ? minval : float4(candidate, newdist);
    }
}

float4 VoronoiNoise3D_ALU(float3 v, int Quality, bool bTiling, float RepeatSize, bool bDistanceOnly)
{
    float3 fv = frac(v), fv2 = frac(v + 0.5);
    float3 iv = floor(v), iv2 = floor(v + 0.5);

    float4 mindist = float4(0, 0, 0, 100);
    float3 p, offset;

    // Quality 3: 3×3×3 搜索
    if (Quality == 3)
    {
        [unroll(3)] for (offset.x = -1; offset.x <= 1; ++offset.x)
        {
            [unroll(3)] for (offset.y = -1; offset.y <= 1; ++offset.y)
            {
                [unroll(3)] for (offset.z = -1; offset.z <= 1; ++offset.z)
                {
                    p = offset + VoronoiCornerSample(NoiseTileWrap(iv2 + offset, bTiling, RepeatSize), Quality);
                    mindist = VoronoiCompare(mindist, iv2 + p, fv2 - p, bDistanceOnly);
                }
            }
        }
    }
    // Quality 1-2: 基础 2×2×2 搜索
    else
    {
        [unroll(2)] for (offset.x = 0; offset.x <= 1; ++offset.x)
        {
            [unroll(2)] for (offset.y = 0; offset.y <= 1; ++offset.y)
            {
                [unroll(2)] for (offset.z = 0; offset.z <= 1; ++offset.z)
                {
                    p = offset + VoronoiCornerSample(NoiseTileWrap(iv + offset, bTiling, RepeatSize), Quality);
                    mindist = VoronoiCompare(mindist, iv + p, fv - p, bDistanceOnly);

                    // Quality 2: 额外一组半格点偏移点
                    if (Quality == 2)
                    {
                        p = offset + VoronoiCornerSample(NoiseTileWrap(iv2 + offset, bTiling, RepeatSize) + 467, Quality);
                        mindist = VoronoiCompare(mindist, iv2 + p, fv2 - p, bDistanceOnly);
                    }
                }
            }
        }
    }

    // Quality 4: 额外搜索相邻方向
    if (Quality >= 4)
    {
        [unroll(2)] for (offset.x = -1; offset.x <= 2; offset.x += 3)
        {
            [unroll(2)] for (offset.y = 0; offset.y <= 1; ++offset.y)
            {
                [unroll(2)] for (offset.z = 0; offset.z <= 1; ++offset.z)
                {
                    p = offset.xyz + VoronoiCornerSample(NoiseTileWrap(iv + offset.xyz, bTiling, RepeatSize), Quality);
                    mindist = VoronoiCompare(mindist, iv + p, fv - p, bDistanceOnly);

                    p = offset.yzx + VoronoiCornerSample(NoiseTileWrap(iv + offset.yzx, bTiling, RepeatSize), Quality);
                    mindist = VoronoiCompare(mindist, iv + p, fv - p, bDistanceOnly);

                    p = offset.zxy + VoronoiCornerSample(NoiseTileWrap(iv + offset.zxy, bTiling, RepeatSize), Quality);
                    mindist = VoronoiCompare(mindist, iv + p, fv - p, bDistanceOnly);
                }
            }
        }
    }

    // 平方距离 → 真实距离
    return float4(mindist.xyz, sqrt(mindist.w));
}

#endif // TR_UE_NOISE_INCLUDED
