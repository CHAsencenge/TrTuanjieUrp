using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Game.Rendering
{
    /// <summary>
    /// Deferred lighting pass that reads the custom GBuffer and evaluates light contributions.
    /// Renders a full-screen quad per light type, writing results to the camera color target.
    /// Architecture referenced from URP DeferredPass.cs and UE5 DeferredLightPixelShaders.usf.
    /// </summary>
    public class CustomDeferredLightingPass : ScriptableRenderPass
    {
        private static readonly int k_GBuffer0Id = Shader.PropertyToID("_CustomGBuffer0");
        private static readonly int k_GBuffer1Id = Shader.PropertyToID("_CustomGBuffer1");
        private static readonly int k_GBuffer2Id = Shader.PropertyToID("_CustomGBuffer2");
        private static readonly int k_GBuffer3Id = Shader.PropertyToID("_CustomGBuffer3");
        private static readonly int k_GBuffer4Id = Shader.PropertyToID("_CustomGBuffer4");

        private readonly ProfilingSampler _profilingSampler;
        private readonly Material _lightingMaterial;
        private readonly CustomGBufferPass _gbufferPass;

        /// <summary>
        /// Creates a new deferred lighting pass.
        /// </summary>
        /// <param name="lightingShader">Shader used for deferred light evaluation.</param>
        /// <param name="gbufferPass">Reference to the GBuffer pass for accessing RT handles.</param>
        public CustomDeferredLightingPass(Shader lightingShader, CustomGBufferPass gbufferPass)
        {
            _profilingSampler = new ProfilingSampler("Custom Deferred Lighting");

            // Execute right after GBuffer pass
            renderPassEvent = RenderPassEvent.BeforeRenderingOpaques + 1;

            _gbufferPass = gbufferPass;

            // Ensure URP copies depth before this pass runs
            ConfigureInput(ScriptableRenderPassInput.Depth);

            if (lightingShader != null)
            {
                _lightingMaterial = CoreUtils.CreateEngineMaterial(lightingShader);
            }
#if ENABLE_DEBUG_LOG
            else
            {
                Debug.LogError("[CustomDeferredLightingPass] Lighting shader is null!");
            }
#endif
        }

        /// <summary>
        /// Configures the pass to render to the camera color target.
        /// </summary>
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var colorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            var depthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            ConfigureTarget(colorTarget, depthTarget);

            // Do not clear - stencil test limits writes to deferred pixels only
            ConfigureClear(ClearFlag.None, Color.black);
        }

        /// <summary>
        /// Executes deferred lighting: binds GBuffer textures and draws a full-screen triangle.
        /// </summary>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_lightingMaterial == null)
                return;

            var gbuffers = _gbufferPass?.GBufferHandles;
            if (gbuffers == null || gbuffers.Length == 0)
                return;

            var cmd = CommandBufferPool.Get("Custom Deferred Lighting");
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                // Bind GBuffer textures for the lighting shader to read
                BindGBufferTextures(cmd, gbuffers);

                // URP's CopyDepthPass already binds _CameraDepthTexture globally.
                // We request depth input so URP ensures the copy runs before us.

                // Draw full-screen triangle to evaluate deferred lighting
                // Uses 3 vertices procedurally generated in the vertex shader
                cmd.DrawProcedural(
                    Matrix4x4.identity,
                    _lightingMaterial,
                    0,
                    MeshTopology.Triangles,
                    3,
                    1
                );

#if ENABLE_DEBUG_LOG
                Debug.Log("[CustomDeferredLightingPass] Deferred lighting executed");
#endif
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        /// <summary>
        /// Binds GBuffer RT handles as global textures for the lighting shader.
        /// </summary>
        private void BindGBufferTextures(CommandBuffer cmd, RTHandle[] gbuffers)
        {
            if (gbuffers.Length > 0 && gbuffers[0] != null)
                cmd.SetGlobalTexture(k_GBuffer0Id, gbuffers[0]);
            if (gbuffers.Length > 1 && gbuffers[1] != null)
                cmd.SetGlobalTexture(k_GBuffer1Id, gbuffers[1]);
            if (gbuffers.Length > 2 && gbuffers[2] != null)
                cmd.SetGlobalTexture(k_GBuffer2Id, gbuffers[2]);
            if (gbuffers.Length > 3 && gbuffers[3] != null)
                cmd.SetGlobalTexture(k_GBuffer3Id, gbuffers[3]);
            if (gbuffers.Length > 4 && gbuffers[4] != null)
                cmd.SetGlobalTexture(k_GBuffer4Id, gbuffers[4]);
        }

        /// <summary>
        /// Cleans up the lighting material.
        /// </summary>
        public void Dispose()
        {
            if (_lightingMaterial != null)
            {
                CoreUtils.Destroy(_lightingMaterial);
            }
        }
    }
}
