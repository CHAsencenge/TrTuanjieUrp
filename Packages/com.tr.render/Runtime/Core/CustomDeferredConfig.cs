using UnityEngine;
using UnityEngine.Experimental.Rendering;

namespace Game.Rendering
{
    /// <summary>
    /// Configuration asset for the custom deferred rendering pipeline.
    /// Defines GBuffer layout, format, and platform-specific settings.
    /// </summary>
    [CreateAssetMenu(fileName = "CustomDeferredConfig", menuName = "Rendering/Custom Deferred Config")]
    public class CustomDeferredConfig : ScriptableObject
    {
        /// <summary>Target platform profile for GBuffer layout selection.</summary>
        public enum PlatformProfile
        {
            /// <summary>PC: 5 render targets, full precision.</summary>
            PC,
            /// <summary>Mobile: 3 render targets, bandwidth-optimized.</summary>
            Mobile
        }

        [Header("Platform")]
        [SerializeField]
        [Tooltip("Determines GBuffer layout and precision. PC uses 5 RTs, Mobile uses 3 RTs.")]
        private PlatformProfile _platformProfile = PlatformProfile.PC;

        [Header("Debug")]
        [SerializeField]
        [Tooltip("Enable GBuffer debug visualization in Scene view.")]
        private bool _enableDebugView;

        [SerializeField]
        [Tooltip("Which GBuffer target to visualize when debug view is enabled.")]
        private int _debugGBufferIndex;

        /// <summary>Active platform profile.</summary>
        public PlatformProfile Platform => _platformProfile;

        /// <summary>Whether GBuffer debug visualization is enabled.</summary>
        public bool EnableDebugView => _enableDebugView;

        /// <summary>Index of GBuffer target to visualize in debug mode.</summary>
        public int DebugGBufferIndex => _debugGBufferIndex;

        /// <summary>Number of GBuffer render targets for the active platform.</summary>
        public int GBufferCount => _platformProfile == PlatformProfile.PC ? 5 : 3;

        /// <summary>
        /// Returns the GraphicsFormat for each GBuffer render target.
        /// </summary>
        /// <param name="index">GBuffer index (0-based).</param>
        /// <returns>The graphics format for the specified GBuffer target.</returns>
        public GraphicsFormat GetGBufferFormat(int index)
        {
            if (_platformProfile == PlatformProfile.PC)
            {
                return GetPCFormat(index);
            }
            return GetMobileFormat(index);
        }

        private static GraphicsFormat GetPCFormat(int index)
        {
            switch (index)
            {
                case 0: return GraphicsFormat.R8G8B8A8_SRGB;          // BaseColor + PackedFlags
                case 1: return GraphicsFormat.R8G8B8A8_UNorm;         // Normal.xy(Oct) + Smoothness + Metallic
                case 2: return GraphicsFormat.R8G8B8A8_UNorm;         // Specular + AO + CustomData.xy
                case 3: return GraphicsFormat.B10G11R11_UFloatPack32; // Emissive/GI
                case 4: return GraphicsFormat.R8G8B8A8_UNorm;         // CustomData.zw + Extra.xy
                default:
#if ENABLE_DEBUG_LOG
                    Debug.LogError($"[CustomDeferredConfig] Invalid PC GBuffer index: {index}");
#endif
                    return GraphicsFormat.R8G8B8A8_UNorm;
            }
        }

        private static GraphicsFormat GetMobileFormat(int index)
        {
            switch (index)
            {
                case 0: return GraphicsFormat.R8G8B8A8_SRGB;          // BaseColor + PackedFlags
                case 1: return GraphicsFormat.R8G8B8A8_UNorm;         // Normal.xy(Oct) + Smoothness + Metallic
                case 2: return GraphicsFormat.B10G11R11_UFloatPack32; // Emissive/GI
                default:
#if ENABLE_DEBUG_LOG
                    Debug.LogError($"[CustomDeferredConfig] Invalid Mobile GBuffer index: {index}");
#endif
                    return GraphicsFormat.R8G8B8A8_UNorm;
            }
        }
    }
}
