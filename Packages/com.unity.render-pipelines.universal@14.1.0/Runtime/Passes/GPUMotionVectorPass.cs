using System;
using Unity.Collections;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal
{
    sealed class GPUMotionVectorPass : ScriptableRenderPass
    {
        #region Fields
        const string kPreviousViewProjectionNoJitter = "_PrevViewProjMatrix";
        const string kViewProjectionNoJitter = "_NonJitteredViewProjMatrix";
#if ENABLE_VR && ENABLE_XR_MODULE
        const string kPreviousViewProjectionNoJitterStereo = "_PrevViewProjMatrixStereo";
        const string kViewProjectionNoJitterStereo = "_NonJitteredViewProjMatrixStereo";
#endif
        RTHandle m_Color;
        RTHandle m_Depth;
        readonly Material m_GpuMotionVectorMaterial;
        private PassData m_PassData;
        #endregion

        #region Constructors
        internal GPUMotionVectorPass(RenderPassEvent evt, Material material)
        {
            renderPassEvent = evt;
            m_GpuMotionVectorMaterial = material;
            m_PassData = new PassData();
            base.profilingSampler = ProfilingSampler.Get(URPProfileId.GPUMotionVectors);

            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        #endregion

        #region State
        internal void Setup(RTHandle color, RTHandle depth)
        {
            m_Color = color;
            m_Depth = depth;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cmd.SetGlobalTexture(m_Color.name, m_Color.nameID);
            cmd.SetGlobalTexture(m_Depth.name, m_Depth.nameID);
            ConfigureTarget(m_Color, m_Depth);

            ConfigureDepthStoreAction(RenderBufferStoreAction.DontCare);
        }

        #endregion

        #region Execution
        private static void ExecutePass(ScriptableRenderContext context, PassData passData, ref RenderingData renderingData)
        {
            var gpuMotionVectorMaterial = passData.gpuMotionVectorMaterial;

            if (gpuMotionVectorMaterial == null)
                return;

            // Get data
            ref var cameraData = ref renderingData.cameraData;
            Camera camera = cameraData.camera;
            MotionVectorsPersistentData motionData = null;

            if(camera.TryGetComponent<UniversalAdditionalCameraData>(out var additionalCameraData))
                motionData = additionalCameraData.motionVectorsPersistentData;

            if (motionData == null)
                return;

            // Never draw in Preview
            if (camera.cameraType == CameraType.Preview)
                return;

            // Profiling command
            var cmd = renderingData.commandBuffer;
            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.GPUMotionVectors)))
            {
                int passID = motionData.GetXRMultiPassId(ref cameraData);

                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
#if ENABLE_VR && ENABLE_XR_MODULE
                if (cameraData.xr.enabled && cameraData.xr.singlePassEnabled)
                {
                    cmd.SetGlobalMatrixArray(kPreviousViewProjectionNoJitterStereo, motionData.previousViewProjectionStereo);
                    cmd.SetGlobalMatrixArray(kViewProjectionNoJitterStereo, motionData.viewProjectionStereo);
                }
                else
#endif
                {
                    cmd.SetGlobalMatrix(kPreviousViewProjectionNoJitter, motionData.previousViewProjectionStereo[passID]);
                    cmd.SetGlobalMatrix(kViewProjectionNoJitter, motionData.viewProjectionStereo[passID]);
                }

                camera.depthTextureMode |= DepthTextureMode.MotionVectors | DepthTextureMode.Depth;

#if ENABLE_VR && ENABLE_XR_MODULE
            bool foveatedRendering = renderingData.cameraData.xr.supportsFoveatedRendering;
            if (foveatedRendering) cmd.SetFoveatedRenderingMode(FoveatedRenderingMode.Enabled);
#endif
                CoreUtils.DrawFullScreen(cmd, gpuMotionVectorMaterial);
#if ENABLE_VR && ENABLE_XR_MODULE
            if (foveatedRendering) cmd.SetFoveatedRenderingMode(FoveatedRenderingMode.Disabled);
#endif
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_PassData.gpuMotionVectorMaterial = m_GpuMotionVectorMaterial;
            ExecutePass(context, m_PassData, ref renderingData);
        }
        #endregion

        private class PassData
        {
            internal TextureHandle motionVectorColor;
            internal TextureHandle motionVectorDepth;
            internal TextureHandle cameraDepth;
            internal RenderingData renderingData;
            internal Material gpuMotionVectorMaterial;
        }

        internal void Render(RenderGraph renderGraph, ref TextureHandle cameraDepthTexture, in TextureHandle motionVectorColor, in TextureHandle motionVectorDepth, ref RenderingData renderingData)
        {
            using (var builder = renderGraph.AddRenderPass<PassData>("Gpu Driven Motion Vector Pass", out var passData, base.profilingSampler))
            { 
                builder.AllowPassCulling(false);

                passData.motionVectorColor       = builder.UseColorBuffer(motionVectorColor, 0);
                passData.motionVectorDepth       = builder.UseDepthBuffer(motionVectorDepth, DepthAccess.Write);
                passData.cameraDepth             = builder.ReadTexture(cameraDepthTexture);
                passData.renderingData           = renderingData;
                passData.gpuMotionVectorMaterial = m_GpuMotionVectorMaterial;

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    ExecutePass(context.renderContext, data, ref data.renderingData);
                    data.renderingData.commandBuffer.SetGlobalTexture("_MotionVectorTexture", data.motionVectorColor);
                });

                return;
            }
        }

        public void Dispose()
        {

        }
    }
}
#endif
