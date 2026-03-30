using System;
using System.Collections.Generic;
using UnityEngine.Assertions;
using UnityEngine.Experimental.Rendering;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    public class ReflectionProbeAtlas
    {
        int m_AtlasWidth;
        int m_AtlasHeight;
        int m_AtlasMipCount;

        public Vector4[] m_ScaleOffset;

        Dictionary<int, (uint, int)> m_TextureLRUAndHash = new Dictionary<int, (uint, int)>();      // <textureID, (lastRenderFrame, renderHash)>
        List<(int, uint)> m_TextureLRUSorted = new List<(int, uint)>();                             // <(textureID, lastRenderFrame)>

        uint m_CurrentRender;

        RTHandle m_AtlasTexture;
        Texture2DAtlasDynamic m_Atlas;
        int m_AtlasAllocatedArea;

        bool m_NeedRelayout = false;

        const int k_MipPadding = 3;
        const int k_TexelPadding = (1 << k_MipPadding) * 2;
        const int k_MaxTexturesInAtlas = 2048;

        static readonly string s_UpdateReflectionProbeAtlas = "Update Reflection Probe Atlas";
        private static readonly ProfilingSampler s_ProfilingUpdateReflectionProbeAtlas = new ProfilingSampler(s_UpdateReflectionProbeAtlas);

        static class ShaderProperties
        {
            public static readonly int Atlas = Shader.PropertyToID("_ReflectionAtlas");
            public static readonly int CubeScaleOffset = Shader.PropertyToID("_ReflectionProbeScaleOffset");
            public static readonly int ReflectionPaddingData = Shader.PropertyToID("_ReflectionPaddingData");
        }

        public ReflectionProbeAtlas()
        {
            int maxProbes = UniversalRenderPipeline.maxVisibleReflectionProbes;
            m_ScaleOffset = new Vector4[maxProbes];
            m_CurrentRender = 0;
        }
        
        public void Init(Vector2Int atlasSize)
        {
            Assert.IsTrue(Mathf.IsPowerOfTwo(atlasSize.x) && Mathf.IsPowerOfTwo(atlasSize.y));
            if (IsInitialized() && atlasSize.x == m_AtlasWidth && atlasSize.y == m_AtlasHeight)
                return;

            if (IsInitialized())
                ReleaseAtlas();

            m_AtlasWidth = atlasSize.x;
            m_AtlasHeight = atlasSize.y;
            m_AtlasMipCount = Mathf.FloorToInt(Mathf.Log(Mathf.Max(m_AtlasWidth, m_AtlasHeight), 2)) + 1;

            m_AtlasTexture = RTHandles.Alloc(
                width: atlasSize.x,
                height: atlasSize.y,
                slices: 1,
                dimension: TextureDimension.Tex2D,
                filterMode: FilterMode.Trilinear,
                colorFormat: GraphicsFormat.B10G11R11_UFloatPack32,
                wrapMode: TextureWrapMode.Clamp,
                useMipMap: true,
                autoGenerateMips: false,
                name: "ReflectionProbeTextureAtlas"
                );

            m_Atlas = new Texture2DAtlasDynamic(atlasSize.x, atlasSize.y, k_MaxTexturesInAtlas, m_AtlasTexture);
            m_AtlasAllocatedArea = 0;
        }

        public void NewRender()
        {
            ++m_CurrentRender;
            m_TextureLRUSorted.Clear();

            foreach (var pair in m_TextureLRUAndHash)
            {
                m_TextureLRUSorted.Add((pair.Key, pair.Value.Item1));
            }

            m_TextureLRUSorted.Sort((a, b) => { return b.Item2.CompareTo(a.Item2); });

            if (m_NeedRelayout)
                RelayoutTextureAtlas();
        }

        private void ReleaseAtlas()
        {
            m_Atlas?.Release();
            m_Atlas = null;
            m_AtlasTexture?.Release();
            m_AtlasTexture = null;
        }

        public void Dispose()
        {
            ReleaseAtlas();
        }

        public bool IsInitialized()
        {
            return m_Atlas != null && m_AtlasTexture != null;
        }

        private int GetTextureSizeInAtlas(Texture texture)
        {
            Assert.IsTrue(texture.dimension == TextureDimension.Cube);

            int textureSize = texture.width;
            if (textureSize < 512)
                textureSize *= 4;
            else
                textureSize *= 2;

            return textureSize;
        }

        private int GetTextureID(Texture texture)
        {
            int textureID = texture.GetInstanceID();
            int textureSize = GetTextureSizeInAtlas(texture);

            // Include texture size in ID using simple hash
            const int kPrime = 31;
            textureID = kPrime * textureID + textureSize;

            return textureID;
        }

        private void RemoveTextureFromAtlas(int textureID)
        {
            Vector4 oldScaleOffset;
            if (m_Atlas.IsCached(out oldScaleOffset, textureID))
            {
                int oldTextureSize = Mathf.RoundToInt(oldScaleOffset.x * m_AtlasWidth);
                m_AtlasAllocatedArea -= oldTextureSize * oldTextureSize;
                m_Atlas.ReleaseTextureSlot(textureID);
                m_TextureLRUAndHash.Remove(textureID);
            }
        }


        private bool TryAllocateTexture(int textureID, int textureSize, ref Vector4 scaleOffset)
        {
            Assert.IsTrue(Mathf.IsPowerOfTwo(textureSize));
            Assert.IsTrue(!m_Atlas.IsCached(out _, textureID));

            // 1.
            // The first direct attempt to find space.
            if (m_Atlas.EnsureTextureSlot(out _, out scaleOffset, textureID, textureSize, textureSize))
                return true;

            // 2.
            // If no space try to remove least recently used entries and find space again.
            for (int textureIndex = m_TextureLRUSorted.Count - 1; textureIndex >= 0; --textureIndex)
            {
                var textureLRU = m_TextureLRUSorted[textureIndex];

                const int k_PreviousRender = 1;

                // Preserve current and previous frame cached entries.
                if (m_CurrentRender - textureLRU.Item2 > k_PreviousRender)
                {
                    RemoveTextureFromAtlas(textureLRU.Item1);
                    m_TextureLRUSorted.RemoveAt(textureIndex);

                    if (m_Atlas.EnsureTextureSlot(out _, out scaleOffset, textureID, textureSize, textureSize))
                        return true;
                }
                else
                {
                    break;
                }
            }

            // 3.
            // Try to downscale texture and find space.
            //if (m_DecreaseResToFit)
            //{
            //    if (m_Atlas.EnsureTextureSlot(out _, out scaleOffset, textureID, textureSize / 2, textureSize / 2))
            //        return true;
            //}

            m_TextureLRUAndHash.Remove(textureID);
            return false;
        }

        private Vector2 GetTextureSizeWithoutPadding(int textureWidth, int textureHeight, int texelPadding)
        {
            int textureWidthWithoutPadding = Mathf.Max(textureWidth - texelPadding, 1);
            int textureHeightWithoutPadding = Mathf.Max(textureHeight - texelPadding, 1);
            return new Vector2(textureWidthWithoutPadding, textureHeightWithoutPadding);
        }

        private void BlitProbe(CommandBuffer cmd, Vector4 scaleOffset, VisibleReflectionProbe probe)
        {
            Texture texture = probe.texture;
            int texelPadding = k_TexelPadding;
            int textureWidthInAtlas = Mathf.RoundToInt(scaleOffset.x * m_AtlasWidth);
            int textureHeightInAtlas = Mathf.RoundToInt(scaleOffset.y * m_AtlasHeight);
            Assert.IsTrue(textureWidthInAtlas == textureHeightInAtlas);

            Vector2 textureSizeWithoutPadding = GetTextureSizeWithoutPadding(textureWidthInAtlas, textureHeightInAtlas, texelPadding);
            bool bilinear = texture.filterMode != FilterMode.Point;

            for (int mipLevel = 0; mipLevel < m_AtlasMipCount; ++mipLevel)
            {
                if (mipLevel > k_MipPadding)
                    texelPadding *= 2;

                cmd.SetRenderTarget(m_AtlasTexture, mipLevel);
                Blitter.BlitCubeToOctahedral2DQuadWithPadding(cmd, texture, textureSizeWithoutPadding, scaleOffset, mipLevel, bilinear, texelPadding, probe.hdrData);
            }
        }

        private void UpdateProbe(CommandBuffer cmd, VisibleReflectionProbe probe, ref Vector4 scaleOffset)
        {
            using (new ProfilingScope(cmd, s_ProfilingUpdateReflectionProbeAtlas))
            {
                Texture texture = probe.texture;
                int textureID = GetTextureID(texture);
                int textureSize = GetTextureSizeInAtlas(texture);

                if (!m_Atlas.IsCached(out scaleOffset, textureID))
                {
                    int atlasArea = m_AtlasWidth * m_AtlasHeight;
                    if (TryAllocateTexture(textureID, textureSize, ref scaleOffset))
                    {
                        m_AtlasAllocatedArea += textureSize * textureSize;
                        Assert.IsTrue(m_AtlasAllocatedArea <= atlasArea);
                    }
                    else
                    {
                        if (m_AtlasAllocatedArea + textureSize * textureSize < atlasArea)
                        {
                            m_NeedRelayout = true;
                        }
                        else
                        {
                            Debug.LogError("No more space in Reflection Probe Atlas. Please increase the size of Reflection Probe Atlas in URP Asset, or reduce resolution of individual reflection probe.");
                        }
                        return;
                    }
                }

                BlitProbe(cmd, scaleOffset, probe);
            }
        }

        private bool NeedsUpdate(Texture texture, ref Vector4 scaleOffset)
        {
            int textureID = GetTextureID(texture);
            int textureHash = CoreUtils.GetTextureHash(texture);

            bool needsUpdate = false;

            if (!m_Atlas.IsCached(out scaleOffset, textureID))
            {
                needsUpdate = true;
            }
            else if (!m_TextureLRUAndHash.TryGetValue(textureID, out (uint, int hash) entry) || textureHash != entry.hash)
            {
                needsUpdate = true;
            }

            m_TextureLRUAndHash[textureID] = (m_CurrentRender, textureHash);

            return needsUpdate;
        }

        private Vector4 FetchCubeReflectionProbe(CommandBuffer cmd, VisibleReflectionProbe probe)
        {
            Texture texture = probe.texture;
            Vector4 scaleOffset = Vector4.zero;

            if (texture != null)
            {
                Assert.IsTrue(texture.width == texture.height);
                Assert.IsTrue(texture.dimension == TextureDimension.Cube);

                if (NeedsUpdate(texture, ref scaleOffset))
                {
                    UpdateProbe(cmd, probe, ref scaleOffset);
                }
            }

            return scaleOffset;
        }

        public Vector4 GetAtlasPaddingData()
        {
            return new Vector4((float)k_TexelPadding / m_AtlasWidth, (float)k_TexelPadding / m_AtlasHeight, k_MipPadding, 0.0f);
        }

        public void ProcessVisibleReflectionProbes(CommandBuffer cmd, CullingResults cullResults)
        {
            var reflectionProbes = cullResults.activeReflectionProbes;
            int reflectionProbeCount = Math.Min(reflectionProbes.Length, UniversalRenderPipeline.maxVisibleReflectionProbes);

            for (int i = 0; i < reflectionProbeCount; ++i)
            {
                VisibleReflectionProbe probe = reflectionProbes[i];
                m_ScaleOffset[i] = FetchCubeReflectionProbe(cmd, probe);
            }

            cmd.SetGlobalTexture(ShaderProperties.Atlas, m_AtlasTexture);
            cmd.SetGlobalVector(ShaderProperties.ReflectionPaddingData, GetAtlasPaddingData());
        }

        private bool RelayoutTextureAtlas()
        {
            using (ListPool<(int textureID, Vector4 scaleOffset)>.Get(out var atlasEntries))
            {
                bool success = true;
                atlasEntries.Capacity = m_TextureLRUAndHash.Count;

                foreach (var pair in m_TextureLRUAndHash)
                {
                    if (m_Atlas.IsCached(out var scaleOffset, pair.Key))
                        atlasEntries.Add((pair.Key, scaleOffset));
                }

                atlasEntries.Sort((a, b) => { return b.scaleOffset.x.CompareTo(a.scaleOffset.x); });

                m_Atlas.ResetAllocator();

                foreach (var atlasEntry in atlasEntries)
                {
                    int textureWidth = Mathf.RoundToInt(atlasEntry.scaleOffset.x * m_AtlasWidth);
                    int textureHeight = Mathf.RoundToInt(atlasEntry.scaleOffset.y * m_AtlasHeight);

                    if (m_Atlas.EnsureTextureSlot(out _, out Vector4 scaleOffset, atlasEntry.textureID, textureWidth, textureHeight))
                    {
                        var textureOffset = new Vector2Int(Mathf.FloorToInt(atlasEntry.scaleOffset.z * m_AtlasWidth), Mathf.FloorToInt(atlasEntry.scaleOffset.w * m_AtlasHeight));
                        var newTextureOffset = new Vector2Int(Mathf.FloorToInt(scaleOffset.z * m_AtlasWidth), Mathf.FloorToInt(scaleOffset.w * m_AtlasHeight));

                        if (textureOffset != newTextureOffset)
                        {
                            var LRUAndHash = m_TextureLRUAndHash[atlasEntry.textureID];
                            LRUAndHash.Item2 = 0;
                            m_TextureLRUAndHash[atlasEntry.textureID] = LRUAndHash;
                        }
                    }
                    else
                    {
                        m_TextureLRUAndHash.Remove(atlasEntry.textureID);
                        success = false;
                    }
                }

                m_NeedRelayout = false;

                return success;
            }
        }
    }

}
#endif
