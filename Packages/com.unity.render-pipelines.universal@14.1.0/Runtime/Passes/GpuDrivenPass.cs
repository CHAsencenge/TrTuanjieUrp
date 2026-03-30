using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;
using System.Data;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    public class GPUDrivenPass : ScriptableRenderPass
    {
        RTHandle preDepthHandle;
        private GDRPShaderData m_PassData;
        private RenderPassEvent m_event;

        public GPUDrivenPass(RenderPassEvent evt)
        {
            base.profilingSampler = new ProfilingSampler(nameof(GPUDrivenPass));
            base.useNativeRenderPass = false;
            m_event = evt;
            m_PassData = new GDRPShaderData();
        }

        public void Setup(RTHandle depthAttachmentHandle, ref RenderingData renderingData, int afterFinalBlitPassQueueOffset)
        {
#if UNITY_EDITOR
            if (GL.wireframe)
            {
                //if wireframe, put GDRP process behind the finalblit in case the wireframe is overwritten.
                renderPassEvent = RenderPassEvent.AfterRendering + afterFinalBlitPassQueueOffset;
            }
            else
#endif
            {
                renderPassEvent = m_event;
            }

            preDepthHandle = depthAttachmentHandle;

            int rtWidth = renderingData.cameraData.cameraTargetDescriptor.width;
            int rtHeight = renderingData.cameraData.cameraTargetDescriptor.height;
            GPUDriven.Manager.CreateMaterialDepth(rtWidth, rtHeight);
        }

        public void Dispose()
        {

        }

        /// <inheritdoc/>
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            CameraData cameraData = renderingData.cameraData;
            m_PassData.camera = cameraData.camera;
            m_PassData.depth = preDepthHandle;
            m_PassData.x = 0;
            m_PassData.y = 0;
            m_PassData.width = cameraData.cameraTargetDescriptor.width;
            m_PassData.height = cameraData.cameraTargetDescriptor.height;
            m_PassData.rtWidth = cameraData.cameraTargetDescriptor.width;
            m_PassData.rtHeight = cameraData.cameraTargetDescriptor.height;
            m_PassData.wireframe = GL.wireframe;
            m_PassData.isBakeReflectionProbe = false;   // @TODO: Find if there is existing variable in URP that can indicate Bake Reflection Probe.
            m_PassData.isCameraRelative = false;        // URP do not support Camera Relative Rendering.
            {
                // TODO：eyeIndex could be only ZERO for now, need to support xr mode and multiple eyeIndex later
                int eyeIndex = 0;
                GPUDriven.Manager.SetJitterProjectionMatrix(cameraData.GetProjectionMatrix(eyeIndex));
            }

        }

        /// <inheritdoc/>
        public void ExecutePass(ScriptableRenderContext context, GDRPShaderData data, CommandBuffer cmd)
        {
            UnityEngine.GPUDriven.GDRPContext GDRPContext = new UnityEngine.GPUDriven.GDRPContext();
            GDRPContext.camera = data.camera;
            GDRPContext.depth = data.depth;
            GDRPContext.viewportX = data.x;
            GDRPContext.viewportY = data.y;
            GDRPContext.viewportWidth = data.width;
            GDRPContext.viewportHeight = data.height;
            GDRPContext.rtWidth = data.rtWidth;
            GDRPContext.rtHeight = data.rtHeight;
            GDRPContext.wireframe = data.wireframe;
            GDRPContext.isBakeReflectionProbe = data.isBakeReflectionProbe;

            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.ExecuteGPUDrivenPipeline)))
            {
                GPUDriven.Manager.ExecuteGPUDrivenPipeline(cmd, GDRPContext);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            ExecutePass(context, m_PassData, renderingData.commandBuffer);
        }

        public class GDRPShaderData
        {
            public Camera camera;
            public RenderTexture depth;
            public int x, y, width, height;
            public int rtWidth, rtHeight;
            public bool wireframe;
            public bool isBakeReflectionProbe;
            public bool isCameraRelative;
        }

        internal void Render(RenderGraph renderGraph, in TextureHandle depthTexture, ref RenderingData renderingData)
        {
            using (var builder = renderGraph.AddRenderPass<GDRPShaderData>("Execute GDRP", out var passData, base.profilingSampler))
            {
                passData.depth = builder.UseDepthBuffer(depthTexture, DepthAccess.ReadWrite);
                passData.camera = renderingData.cameraData.camera;
                passData.x = 0;
                passData.y = 0;
                passData.width = renderingData.cameraData.cameraTargetDescriptor.width;
                passData.height = renderingData.cameraData.cameraTargetDescriptor.height;
                passData.rtWidth = renderingData.cameraData.cameraTargetDescriptor.width;
                passData.rtHeight = renderingData.cameraData.cameraTargetDescriptor.height;
                passData.wireframe = GL.wireframe;
                passData.isBakeReflectionProbe = false;
                passData.isCameraRelative = false;

                builder.SetRenderFunc((GDRPShaderData data, RenderGraphContext context) =>
                {
                    ExecutePass(context.renderContext, data, context.cmd);
                });

                return;
            }
        }
    }
}
#endif
