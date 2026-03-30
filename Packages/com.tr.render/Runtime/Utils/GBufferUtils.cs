using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Game.Rendering
{
    /// <summary>
    /// Utility class for managing GBuffer render target allocation and lifecycle.
    /// Handles RTHandle creation, resizing, and disposal.
    /// </summary>
    public static class GBufferUtils
    {
        /// <summary>
        /// Allocates GBuffer render target handles based on the provided config.
        /// </summary>
        /// <param name="config">GBuffer configuration defining formats and count.</param>
        /// <param name="handles">Pre-allocated array to fill with RTHandles. Must match config.GBufferCount.</param>
        public static void AllocateGBuffers(CustomDeferredConfig config, RTHandle[] handles)
        {
            for (int i = 0; i < config.GBufferCount; i++)
            {
                if (handles[i] != null)
                    continue;

                var format = config.GetGBufferFormat(i);
                handles[i] = RTHandles.Alloc(
                    Vector2.one,
                    colorFormat: format,
                    filterMode: FilterMode.Point,
                    wrapMode: TextureWrapMode.Clamp,
                    name: $"_CustomGBuffer{i}"
                );

#if ENABLE_DEBUG_LOG
                Debug.Log($"[GBufferUtils] Allocated GBuffer{i}: {format}");
#endif
            }
        }

        /// <summary>
        /// Releases all GBuffer render target handles.
        /// </summary>
        /// <param name="handles">Array of RTHandles to release.</param>
        public static void ReleaseGBuffers(RTHandle[] handles)
        {
            if (handles == null)
                return;

            for (int i = 0; i < handles.Length; i++)
            {
                if (handles[i] != null)
                {
                    RTHandles.Release(handles[i]);
                    handles[i] = null;
                }
            }
        }

        /// <summary>
        /// Packs a ShadingModelId and MaterialFlags into a single byte.
        /// Lower 4 bits = ShadingModelId, Upper 4 bits = MaterialFlags.
        /// </summary>
        /// <param name="modelId">Shading model identifier (0-15).</param>
        /// <param name="flags">Material flags bitmask.</param>
        /// <returns>Packed byte value normalized to [0,1] for shader use.</returns>
        public static float PackShadingModelAndFlags(ShadingModelId modelId, MaterialFlags flags)
        {
            byte packed = (byte)((byte)modelId | ((byte)flags << 4));
            return packed / 255.0f;
        }

        /// <summary>
        /// Unpacks ShadingModelId from a packed byte value.
        /// </summary>
        /// <param name="packedValue">Normalized [0,1] packed value from GBuffer0.a.</param>
        /// <returns>The shading model identifier.</returns>
        public static ShadingModelId UnpackShadingModelId(float packedValue)
        {
            byte packed = (byte)Mathf.RoundToInt(packedValue * 255.0f);
            return (ShadingModelId)(packed & 0x0F);
        }

        /// <summary>
        /// Unpacks MaterialFlags from a packed byte value.
        /// </summary>
        /// <param name="packedValue">Normalized [0,1] packed value from GBuffer0.a.</param>
        /// <returns>The material flags bitmask.</returns>
        public static MaterialFlags UnpackMaterialFlags(float packedValue)
        {
            byte packed = (byte)Mathf.RoundToInt(packedValue * 255.0f);
            return (MaterialFlags)((packed >> 4) & 0x0F);
        }
    }
}
