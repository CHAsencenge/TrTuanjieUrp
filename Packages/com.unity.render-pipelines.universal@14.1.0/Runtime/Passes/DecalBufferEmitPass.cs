#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    /// <summary>
    /// Render all VG objects' rendering layer into the give rendering layer buffer.
    /// </summary>
    public class DecalBufferEmitPass : ScriptableRenderPass
    {
        // internal
        internal bool enableRenderingLayers { get; set; } = false;

        // Private
        private RTHandle depthHandle { get; set; }
        private RTHandle renderingLayerHandle { get; set; }
        private PassData m_PassData;
        private readonly Material m_DecalBufferEmitMaterial;

        // Constants and Statics

        // Classes
        private class PassData
        {
            internal bool enableRenderingLayers;
            internal Material decalBufferEmitMaterial;
        }

        /// <summary>
        /// Creates a new <c>DecalBufferEmitPass</c> instance.
        /// </summary>
        /// <param name="evt">The <c>RenderPassEvent</c> to use.</param>
        /// <param name="material">The material to use.</param>
        /// <seealso cref="RenderPassEvent"/>
        /// <seealso cref="Material"/>
        public DecalBufferEmitPass(RenderPassEvent evt, Material material)
        {
            profilingSampler = new ProfilingSampler(nameof(DecalBufferEmitPass));
            m_PassData = new PassData();
            renderPassEvent = evt;
            m_DecalBufferEmitMaterial = material;
        }

        public void Setup(bool enableRenderingLayers)
        {
            this.enableRenderingLayers = enableRenderingLayers;
        }

        public void Setup(bool enableRenderingLayers, RTHandle depthHandle, RTHandle decalLayerHandle)
        {
            Setup(enableRenderingLayers);
            this.depthHandle = depthHandle;
            this.renderingLayerHandle = decalLayerHandle;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (enableRenderingLayers)
            {
                if (renderingData.cameraData.renderer.useDepthPriming && (renderingData.cameraData.renderType == CameraRenderType.Base || renderingData.cameraData.clearDepth))
                    ConfigureTarget(renderingLayerHandle, renderingData.cameraData.renderer.cameraDepthTargetHandle);
                else
                    ConfigureTarget(renderingLayerHandle, depthHandle);
            }

            // We should remain rendering layer from Non-VG, so do not clear here.
            // ConfigureClear(ClearFlag.All, Color.black);
        }

        private static void ExecutePass(ScriptableRenderContext context, PassData passData, ref RenderingData renderingData)
        {
            var cmd = renderingData.commandBuffer;
            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.DecalBufferEmit)))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                if (passData.enableRenderingLayers)
                {
                    CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.WriteRenderingLayers, true);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();

                    // Draw
                    CoreUtils.DrawFullScreen(cmd, passData.decalBufferEmitMaterial);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();

                    CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.WriteRenderingLayers, false);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                }
            }
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_PassData.enableRenderingLayers = enableRenderingLayers;
            m_PassData.decalBufferEmitMaterial = m_DecalBufferEmitMaterial;

            ExecutePass(context, m_PassData, ref renderingData);
        }
    }
}
#endif
