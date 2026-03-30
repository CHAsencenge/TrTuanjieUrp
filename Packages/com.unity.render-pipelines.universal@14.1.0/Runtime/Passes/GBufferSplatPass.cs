using UnityEngine.Experimental.GlobalIllumination;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Profiling;
using Unity.Collections;
using UnityEngine.Experimental.Rendering.RenderGraphModule;
using System.Collections.Generic;
using System.Linq;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    // Render all tiled-based deferred lights.
    internal class GBufferSplatPass : ScriptableRenderPass
    {
        static readonly int s_CameraNormalsTextureID = Shader.PropertyToID("_CameraNormalsTexture");
        static ShaderTagId s_ShaderTagUniversalGBufferSplat = new ShaderTagId("UniversalGBufferSplat");

        ProfilingSampler m_ProfilingSampler = new ProfilingSampler("Render GBuffer Splat");

        DeferredLights m_DeferredLights;

        FilteringSettings m_FilteringSettings;
        RenderStateBlock m_RenderStateBlock;
        private PassData m_PassData;

        public GBufferSplatPass(RenderPassEvent evt, RenderQueueRange renderQueueRange, LayerMask layerMask, DeferredLights deferredLights)
        {
            base.profilingSampler = new ProfilingSampler(nameof(GBufferSplatPass));
            base.renderPassEvent = evt;
            base.useNativeRenderPass = false;
            m_PassData = new PassData();

            m_DeferredLights = deferredLights;
            m_FilteringSettings = new FilteringSettings(renderQueueRange, layerMask);
            m_RenderStateBlock = new RenderStateBlock(RenderStateMask.Nothing);

        }

        public void Dispose()
        {
            //m_DeferredLights.ReleaseGbufferResources();
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            RTHandle[] gbufferAttachments = m_DeferredLights.GbufferAttachments;

            if (cmd != null)
            {
                var allocateGbufferDepth = true;
                if (m_DeferredLights.UseRenderPass && (m_DeferredLights.DepthCopyTexture != null && m_DeferredLights.DepthCopyTexture.rt != null))
                {
                    m_DeferredLights.GbufferAttachments[m_DeferredLights.GbufferDepthIndex] = m_DeferredLights.DepthCopyTexture;
                    allocateGbufferDepth = false;
                }
                // Create and declare the render targets used in the pass
                for (int i = 0; i < gbufferAttachments.Length; ++i)
                {
                    // Lighting buffer has already been declared with line ConfigureCameraTarget(m_ActiveCameraColorAttachment.Identifier(), ...) in DeferredRenderer.Setup
                    if (i == m_DeferredLights.GBufferLightingIndex)
                        continue;

                    // Normal buffer may have already been created if there was a depthNormal prepass before.
                    // DepthNormal prepass is needed for forward-only materials when SSAO is generated between gbuffer and deferred lighting pass.
                    if (i == m_DeferredLights.GBufferNormalSmoothnessIndex && m_DeferredLights.HasNormalPrepass)
                        continue;

                    if (i == m_DeferredLights.GbufferDepthIndex && !allocateGbufferDepth)
                        continue;

                    // No need to setup temporaryRTs if we are using input attachments as they will be Memoryless
                    if (m_DeferredLights.UseRenderPass && i != m_DeferredLights.GBufferRenderingLayers && (i != m_DeferredLights.GbufferDepthIndex && !m_DeferredLights.HasDepthPrepass))
                        continue;

                    m_DeferredLights.ReAllocateGBufferIfNeeded(cameraTextureDescriptor, i);

                    cmd.SetGlobalTexture(m_DeferredLights.GbufferAttachments[i].name, m_DeferredLights.GbufferAttachments[i].nameID);
                }
            }

            if (m_DeferredLights.UseRenderPass)
                m_DeferredLights.UpdateDeferredInputAttachments();

            //RenderTexture materialDepth = GPUDriven.Manager.GetMaterialDepth();
            int materialDepthInstanceID = GPUDriven.Manager.GetMaterialDepthInstanceID();
            RenderTargetIdentifier materialDepthIdentifier = new RenderTargetIdentifier(BuiltinRenderTextureType.RenderTexture, materialDepthInstanceID, 0, CubemapFace.Unknown, 0);
            ConfigureTarget(m_DeferredLights.GbufferAttachments, materialDepthIdentifier, m_DeferredLights.GbufferFormats);
            // We must explicitly specify we don't want any clear to avoid unwanted side-effects.
            // ScriptableRenderer will implicitly force a clear the first time the camera color/depth targets are bound.
            ConfigureClear(ClearFlag.None, Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = renderingData.commandBuffer;

            m_PassData.filteringSettings = m_FilteringSettings;
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                m_PassData.deferredLights = m_DeferredLights;

                // User can stack several scriptable renderers during rendering but deferred renderer should only lit pixels added by this gbuffer pass.
                // If we detect we are in such case (camera is in overlay mode), we clear the highest bits of stencil we have control of and use them to
                // mark what pixel to shade during deferred pass. Gbuffer will always mark pixels using their material types.


                ref CameraData cameraData = ref renderingData.cameraData;
                ShaderTagId lightModeTag = s_ShaderTagUniversalGBufferSplat;
                m_PassData.drawingSettings = CreateDrawingSettings(lightModeTag, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                ExecutePass(context, m_PassData, ref renderingData);

                // If any sub-system needs camera normal texture, make it available.
                // Input attachments will only be used when this is not needed so safe to skip in that case
                if (!m_DeferredLights.UseRenderPass)
                    renderingData.commandBuffer.SetGlobalTexture(s_CameraNormalsTextureID, m_DeferredLights.GbufferAttachments[m_DeferredLights.GBufferNormalSmoothnessIndex]);
            }
        }

        static void ExecutePass(ScriptableRenderContext context, PassData data, ref RenderingData renderingData, bool useRenderGraph = false)
        {
            bool usesRenderingLayers = data.deferredLights.UseRenderingLayers && !data.deferredLights.HasRenderingLayerPrepass;
            if (usesRenderingLayers)
                CoreUtils.SetKeyword(renderingData.commandBuffer, ShaderKeywordStrings.WriteRenderingLayers, true);

            context.ExecuteCommandBuffer(renderingData.commandBuffer);
            renderingData.commandBuffer.Clear();

            if (data.deferredLights.IsOverlay)
            {
                data.deferredLights.ClearStencilPartial(renderingData.commandBuffer);
                context.ExecuteCommandBuffer(renderingData.commandBuffer);
                renderingData.commandBuffer.Clear();
            }

            RendererUtils.RendererListDesc rendererListDesc = new RendererUtils.RendererListDesc(s_ShaderTagUniversalGBufferSplat, renderingData.cullResults, renderingData.cameraData.camera);
            rendererListDesc.useGPUDrivenPipeline = 1;
            rendererListDesc.rendererConfiguration = renderingData.perObjectData;
            RendererList rendererList = context.CreateRendererList(rendererListDesc);

            CoreUtils.DrawRendererList(context, renderingData.commandBuffer, rendererList);

            context.ExecuteCommandBuffer(renderingData.commandBuffer);
            renderingData.commandBuffer.Clear();

            // If any sub-system needs camera normal texture, make it available.
            // Input attachments will only be used when this is not needed so safe to skip in that case
            if (!data.deferredLights.UseRenderPass)
                renderingData.commandBuffer.SetGlobalTexture(s_CameraNormalsTextureID, data.deferredLights.GbufferAttachments[data.deferredLights.GBufferNormalSmoothnessIndex]);

            // Clean up
            if (usesRenderingLayers)
            {
                CoreUtils.SetKeyword(renderingData.commandBuffer, ShaderKeywordStrings.WriteRenderingLayers, false);
                context.ExecuteCommandBuffer(renderingData.commandBuffer);
                renderingData.commandBuffer.Clear();
            }
        }

        private class PassData
        {
            internal TextureHandle[] gbuffer;

            internal RenderingData renderingData;

            internal DeferredLights deferredLights;
            internal FilteringSettings filteringSettings;
            internal DrawingSettings drawingSettings;
        }

        internal void Render(RenderGraph renderGraph, TextureHandle cameraColor, TextureHandle cameraDepth,
            ref RenderingData renderingData, ref UniversalRenderer.RenderGraphFrameResources frameResources)
        {
            using (var builder = renderGraph.AddRenderPass<PassData>("GBuffer Splat Pass", out var passData, m_ProfilingSampler))
            {
                passData.gbuffer = frameResources.gbuffer = m_DeferredLights.GbufferTextureHandles;
                for (int i = 0; i < m_DeferredLights.GBufferSliceCount; i++)
                {
                    var gbufferSlice = renderingData.cameraData.cameraTargetDescriptor;
                    gbufferSlice.depthBufferBits = 0; // make sure no depth surface is actually created
                    gbufferSlice.stencilFormat = GraphicsFormat.None;

                    if (i != m_DeferredLights.GBufferLightingIndex)
                    {
                        gbufferSlice.graphicsFormat = m_DeferredLights.GetGBufferFormat(i);
                        frameResources.gbuffer[i] = UniversalRenderer.CreateRenderGraphTexture(renderGraph, gbufferSlice, DeferredLights.k_GBufferNames[i], true);
                    }
                    else
                    {
                        frameResources.gbuffer[i] = cameraColor;
                    }
                    passData.gbuffer[i] = builder.UseColorBuffer(frameResources.gbuffer[i], i);
                }

                passData.deferredLights = m_DeferredLights;

                passData.renderingData = renderingData;

                builder.AllowPassCulling(false);

                passData.filteringSettings = m_FilteringSettings;
                ShaderTagId lightModeTag = s_ShaderTagUniversalGBufferSplat;
                passData.drawingSettings = CreateDrawingSettings(lightModeTag, ref passData.renderingData, renderingData.cameraData.defaultOpaqueSortFlags);

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    RenderTargetIdentifier[] list = context.renderGraphPool.GetTempArray<RenderTargetIdentifier>(m_DeferredLights.GBufferSliceCount);
                    for (int i = 0; i < m_DeferredLights.GBufferSliceCount; ++i)
                    {
                        list[i] = data.gbuffer[i];
                    }

                    RenderTexture materialDepth = GPUDriven.Manager.GetMaterialDepth();
                    CoreUtils.SetRenderTarget(context.cmd, list, materialDepth);

                    ExecutePass(context.renderContext, data, ref data.renderingData, true);
                });

            }
            using (var builder = renderGraph.AddRenderPass<PassData>("Set GBuffer Globals", out var passData, m_ProfilingSampler))
            {
                passData.gbuffer = frameResources.gbuffer = m_DeferredLights.GbufferTextureHandles;
                for (int i = 0; i < m_DeferredLights.GBufferSliceCount; i++)
                {
                    passData.gbuffer[i] = builder.UseColorBuffer(frameResources.gbuffer[i], i);
                }

                passData.renderingData = renderingData;
                passData.deferredLights = m_DeferredLights;

                builder.AllowPassCulling(false);

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    for (int i = 0; i < data.gbuffer.Length; i++)
                    {
                        if (i != data.deferredLights.GBufferLightingIndex)
                            data.renderingData.commandBuffer.SetGlobalTexture(DeferredLights.k_GBufferNames[i], data.gbuffer[i]);
                    }
                });
            }
        }
    }
}
#endif
