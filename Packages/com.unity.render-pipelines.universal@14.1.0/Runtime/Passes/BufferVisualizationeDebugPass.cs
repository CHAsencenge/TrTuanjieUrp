using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal
{
    internal class BufferVisualizationeDebugPass : ScriptableRenderPass
    {
        GPUDrivenDebugOverlayPassData m_passData;

        class GPUDrivenDebugOverlayPassData
        {
            public DebugOverlay debugOverlay;
            public Material debugVisibilityMaterial;
            public Material debugMaterialIDMaterial;
            public DebugBufferVisualization debugBufferVisualizationMode;
        }

        public BufferVisualizationeDebugPass(Material visibilityMaterial, Material materialIDMaterial)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_passData = new GPUDrivenDebugOverlayPassData();
            m_passData.debugOverlay = new DebugOverlay();
            m_passData.debugVisibilityMaterial = visibilityMaterial;
            m_passData.debugMaterialIDMaterial = materialIDMaterial;
        }

        public void Setup(DebugBufferVisualization debugBufferVisualizationMode)
        {
            m_passData.debugBufferVisualizationMode = debugBufferVisualizationMode;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = renderingData.commandBuffer;
            if (CoreUtils.UseGDRP(renderingData.cameraData.camera) && UniversalRenderPipelineAsset.IsURPAssetSupportGDRP())
            {
                switch (m_passData.debugBufferVisualizationMode)
                {
                    case DebugBufferVisualization.None:
                        break;
                    case DebugBufferVisualization.ClusterID:
                        ClusterIDExecutePass(cmd, renderingData);
                        break;
                    case DebugBufferVisualization.TriangleID:
                        TriangleIDExecutePass(cmd, renderingData);
                        break;
                    case DebugBufferVisualization.InstanceID:
                        InstanceIDExecutePass(cmd, renderingData);
                        break;
                    case DebugBufferVisualization.MaterialID:
                        MaterialIDExecutePass(cmd, renderingData);
                        break;
                    case DebugBufferVisualization.MaterialRange:
                        MaterialRangeExecutePass(cmd, renderingData);
                        break;
                }
            }
        }

        private void ClusterIDExecutePass(CommandBuffer cmd, RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("ClusterID FullScreen")))
            {
                var passData = m_passData;
                passData.debugOverlay.SetViewport(cmd);
                var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                CoreUtils.DrawFullScreen(cmd, passData.debugVisibilityMaterial, cameraColorTarget);
            }
        }

        private void TriangleIDExecutePass(CommandBuffer cmd, RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("TriangleID FullScreen")))
            {
                var passData = m_passData;
                passData.debugOverlay.SetViewport(cmd);
                var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                CoreUtils.DrawFullScreen(cmd, passData.debugVisibilityMaterial, cameraColorTarget, null, 1);
            }
        }

        private void InstanceIDExecutePass(CommandBuffer cmd, RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("InstanceID FullScreen")))
            {
                var passData = m_passData;
                passData.debugOverlay.SetViewport(cmd);
                var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                CoreUtils.DrawFullScreen(cmd, passData.debugVisibilityMaterial, cameraColorTarget, null, 2);
            }
        }

        private void MaterialIDExecutePass(CommandBuffer cmd, RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("MaterialID FullScreen")))
            {
                var passData = m_passData;
                passData.debugOverlay.SetViewport(cmd);
                var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                CoreUtils.DrawFullScreen(cmd, passData.debugMaterialIDMaterial, cameraColorTarget, null, 0);
            }
        }

        private void MaterialRangeExecutePass(CommandBuffer cmd, RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("MaterialRange FullScreen")))
            {
                var passData = m_passData;
                var buffer = GPUDriven.Manager.GetMaterialRangeBuffer();
                var cameraData = renderingData.cameraData;
                passData.debugOverlay.SetViewport(cmd);
                Vector2 tileSize = new Vector2(0, 0);
                tileSize.x = (int)(cameraData.pixelWidth) / 64 + 1;
                tileSize.y = (int)(cameraData.pixelHeight) / 64 + 1;
                var finalViewportSize = new Vector2(tileSize.x, tileSize.y);
                var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                passData.debugMaterialIDMaterial.SetBuffer("_MaterialRangeBuffer", buffer);
                passData.debugMaterialIDMaterial.SetVector("_Viewport", finalViewportSize);
                passData.debugMaterialIDMaterial.SetVector("_TileSize", tileSize);
                CoreUtils.DrawFullScreen(cmd, passData.debugMaterialIDMaterial, cameraColorTarget, null, 1);
            }
        }
    }
}
#endif
