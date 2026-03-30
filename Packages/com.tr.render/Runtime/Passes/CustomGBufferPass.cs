using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Game.Rendering
{
    /// <summary>
    /// Renders opaque objects with LightMode "CustomDeferredGBuffer" into custom GBuffer render targets.
    /// Objects without this tag are ignored and continue through URP's default forward path.
    /// Architecture referenced from URP GBufferPass.cs, simplified for custom pipeline.
    /// </summary>
    public class CustomGBufferPass : ScriptableRenderPass
    {
        private static readonly ShaderTagId k_ShaderTagCustomGBuffer = new ShaderTagId("CustomDeferredGBuffer");
        private static readonly int k_GBufferCountPC = 5;

        private readonly ProfilingSampler _profilingSampler;
        private readonly CustomDeferredConfig _config;

        private RTHandle[] _gbufferHandles;
        private RTHandle _depthHandle;
        private FilteringSettings _filteringSettings;

        /// <summary>GBuffer render target handles for external access (lighting pass reads these).</summary>
        public RTHandle[] GBufferHandles => _gbufferHandles;

        /// <summary>
        /// Creates a new CustomGBufferPass.
        /// </summary>
        /// <param name="config">GBuffer format configuration.</param>
        public CustomGBufferPass(CustomDeferredConfig config)
        {
            _config = config;
            _profilingSampler = new ProfilingSampler("Custom Deferred GBuffer");
            renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;

            // Only render opaque geometry in the default render queue range
            _filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
        }

        /// <summary>
        /// Allocates GBuffer render targets and configures them as the pass output.
        /// Called by the pipeline before Execute.
        /// </summary>
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            int gbufferCount = _config.GBufferCount;

            if (_gbufferHandles == null || _gbufferHandles.Length != gbufferCount)
            {
                ReleaseGBuffers();
                _gbufferHandles = new RTHandle[gbufferCount];
            }

            // Allocate each GBuffer RT
            for (int i = 0; i < gbufferCount; i++)
            {
                var format = _config.GetGBufferFormat(i);
                var rtDesc = new RenderTextureDescriptor(desc.width, desc.height)
                {
                    graphicsFormat = format,
                    depthBufferBits = 0,
                    msaaSamples = 1,
                    dimension = UnityEngine.Rendering.TextureDimension.Tex2D
                };

                if (_gbufferHandles[i] == null || _gbufferHandles[i].rt == null ||
                    _gbufferHandles[i].rt.width != desc.width || _gbufferHandles[i].rt.height != desc.height)
                {
                    if (_gbufferHandles[i] != null)
                        RTHandles.Release(_gbufferHandles[i]);

                    _gbufferHandles[i] = RTHandles.Alloc(rtDesc, FilterMode.Point, TextureWrapMode.Clamp, name: $"_CustomGBuffer{i}");
                }

                // Make GBuffer textures globally accessible for the lighting pass
                cmd.SetGlobalTexture($"_CustomGBuffer{i}", _gbufferHandles[i]);
            }

            // Configure MRT output: all GBuffers + camera depth
            _depthHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            ConfigureTarget(_gbufferHandles, _depthHandle);
            ConfigureClear(ClearFlag.Color, Color.clear);
        }

        /// <summary>
        /// Executes the GBuffer pass: draws all opaque objects with the CustomDeferredGBuffer tag.
        /// </summary>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("Custom Deferred GBuffer");
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                // Set up drawing: only objects with LightMode = "CustomDeferredGBuffer"
                var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
                var drawingSettings = CreateDrawingSettings(k_ShaderTagCustomGBuffer, ref renderingData, sortFlags);

                // Draw all matching opaque objects
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);

#if ENABLE_DEBUG_LOG
                Debug.Log("[CustomGBufferPass] GBuffer pass executed");
#endif
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        /// <summary>
        /// Releases GBuffer render target handles.
        /// </summary>
        public void ReleaseGBuffers()
        {
            if (_gbufferHandles == null) return;

            for (int i = 0; i < _gbufferHandles.Length; i++)
            {
                if (_gbufferHandles[i] != null)
                {
                    RTHandles.Release(_gbufferHandles[i]);
                    _gbufferHandles[i] = null;
                }
            }
            _gbufferHandles = null;
        }
    }
}
