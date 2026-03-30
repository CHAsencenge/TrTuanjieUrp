using System;
using UnityEngine.Experimental.Rendering;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    public class CopyDepthPyramidPass : ScriptableRenderPass
    {
        private PassData m_PassData;

        const int targetRes = 512;

        public CopyDepthPyramidPass(RenderPassEvent evt)
        {
            base.profilingSampler = new ProfilingSampler(nameof(CopyDepthPass));
            base.useNativeRenderPass = false;
            m_PassData = new PassData();
            renderPassEvent = evt;
        }
        public void Setup(RTHandle depth)
        {
            m_PassData.depth = depth;
        }

        private class PassData
        {
            internal RenderTexture depth;
            internal RenderTexture depthPyramid;
            internal CommandBuffer cmd;
            internal CameraData cameraData;
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_PassData.cmd = renderingData.commandBuffer;
            m_PassData.cameraData = renderingData.cameraData;
            m_PassData.depthPyramid = GPUDriven.Manager.GetDepthPyramid(renderingData.cameraData.camera);

            ExecutePass(context, m_PassData);
        }

        private static void ExecutePass(ScriptableRenderContext context, PassData passData)
        {
            var cmd = passData.cmd;
            var camera = passData.cameraData.camera;
            var depth = passData.depth;
            var depthPyramid = passData.depthPyramid;

            int curWidth = passData.cameraData.scaledWidth;
            int curHeight = passData.cameraData.scaledHeight;

            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.DepthPyramidForHZBOC)))
            {
                GPUDriven.Manager.ResizeDepth(cmd, camera, depth, depthPyramid, curWidth, curHeight, targetRes);
                GPUDriven.Manager.RenderHizDepthMipmap(cmd, camera, depthPyramid, -1, curWidth, curHeight);
            }
        }
    }
}
#endif
