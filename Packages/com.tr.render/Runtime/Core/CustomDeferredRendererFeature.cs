using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Game.Rendering
{
    /// <summary>
    /// ScriptableRendererFeature that injects the custom deferred rendering pipeline into URP.
    /// Adds a GBuffer pass (BeforeRenderingOpaques) and a Deferred Lighting pass (immediately after).
    /// Objects using LightMode "CustomDeferredGBuffer" are rendered via deferred;
    /// all other objects (including transparents) continue through URP's forward path.
    /// </summary>
    public class CustomDeferredRendererFeature : ScriptableRendererFeature
    {
        [Header("Configuration")]
        [SerializeField]
        [Tooltip("GBuffer layout and platform configuration asset.")]
        private CustomDeferredConfig _config;

        [Header("Shaders")]
        [SerializeField]
        [Tooltip("Shader used for the deferred lighting full-screen pass.")]
        private Shader _deferredLightingShader;

        [Header("Debug")]
        [SerializeField]
        [Tooltip("Enable to log pass execution to console (requires ENABLE_DEBUG_LOG define).")]
        private bool _enableDebugLogs;

        private CustomGBufferPass _gbufferPass;
        private CustomDeferredLightingPass _lightingPass;

        /// <summary>
        /// Creates and initializes the render passes.
        /// Called by URP when the feature is first loaded or settings change.
        /// </summary>
        public override void Create()
        {
            if (_config == null)
            {
#if ENABLE_DEBUG_LOG
                Debug.LogWarning("[CustomDeferredRendererFeature] Config is not assigned. Feature disabled.");
#endif
                return;
            }

            // Resolve deferred lighting shader
            var lightingShader = _deferredLightingShader;
            if (lightingShader == null)
            {
                lightingShader = Shader.Find("Hidden/Custom/DeferredLighting");
            }

            if (lightingShader == null)
            {
#if ENABLE_DEBUG_LOG
                Debug.LogError("[CustomDeferredRendererFeature] Could not find deferred lighting shader!");
#endif
                return;
            }

            _gbufferPass = new CustomGBufferPass(_config);
            _lightingPass = new CustomDeferredLightingPass(lightingShader, _gbufferPass);

#if ENABLE_DEBUG_LOG
            if (_enableDebugLogs)
            {
                Debug.Log($"[CustomDeferredRendererFeature] Created with {_config.GBufferCount} GBuffer targets ({_config.Platform})");
            }
#endif
        }

        /// <summary>
        /// Injects the GBuffer and lighting passes into the renderer's pass queue.
        /// Called every frame for each camera.
        /// </summary>
        /// <param name="renderer">The scriptable renderer to enqueue passes into.</param>
        /// <param name="renderingData">Current frame rendering data.</param>
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (_gbufferPass == null || _lightingPass == null)
                return;

            // Skip for preview cameras and reflection probes
            if (renderingData.cameraData.cameraType == CameraType.Preview ||
                renderingData.cameraData.cameraType == CameraType.Reflection)
                return;

            renderer.EnqueuePass(_gbufferPass);
            renderer.EnqueuePass(_lightingPass);
        }

        /// <summary>
        /// Releases all allocated render resources.
        /// </summary>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _gbufferPass?.ReleaseGBuffers();
                _lightingPass?.Dispose();

                _gbufferPass = null;
                _lightingPass = null;
            }
        }
    }
}
