// 移植自 UE5 Hash.ush
// GPU 哈希函数: MurmurHash3 增量混合 + PCG 哈希

#ifndef TR_UE_HASH_INCLUDED
#define TR_UE_HASH_INCLUDED

//=============================================================================
//  MurmurHash3 — 增量式哈希
//  用法: hash = MurmurMix( MurmurAdd( MurmurAdd(seed, a), b) )
//  适用于将多个整数键合并为单一哈希值
//=============================================================================

// 向哈希状态中混入一个新元素
uint MurmurAdd(uint Hash, uint Element)
{
    Element *= 0xcc9e2d51u;
    Element = (Element << 15) | (Element >> (32 - 15));
    Element *= 0x1b873593u;

    Hash ^= Element;
    Hash = (Hash << 13) | (Hash >> (32 - 13));
    Hash = Hash * 5 + 0xe6546b64u;
    return Hash;
}

// 最终混合步骤 — 雪崩效应，使所有位充分扩散
uint MurmurMix(uint Hash)
{
    Hash ^= Hash >> 16;
    Hash *= 0x85ebca6bu;
    Hash ^= Hash >> 13;
    Hash *= 0xc2b2ae35u;
    Hash ^= Hash >> 16;
    return Hash;
}

//=============================================================================
//  PCG 哈希 — 单值版本
//  [Jarzynski & Olano 2020, "Hash Functions for GPU Rendering"]
//  将单个 uint 映射为伪随机 uint，适合着色器中的简单随机化
//=============================================================================
uint PCGHash(uint Input)
{
    uint State = Input * 747796405u + 2891336453u;
    uint Word = ((State >> ((State >> 28u) + 4u)) ^ State) * 277803737u;
    return (Word >> 22u) ^ Word;
}

#endif // TR_UE_HASH_INCLUDED
