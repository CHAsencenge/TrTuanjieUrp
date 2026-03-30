using System;
using Unity.Collections;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;
using UnityEngine.Experimental.GlobalIllumination;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    internal class StencilSplatPass : ScriptableRenderPass
    {
        static readonly int k_StencilRef = Shader.PropertyToID("_StencilRef");
        static readonly int k_StencilReadMask = Shader.PropertyToID("_StencilReadMask");
        static readonly int k_StencilWriteMask = Shader.PropertyToID("_StencilWriteMask");
        readonly Material m_StencilSplatMaterial;
        RTHandle m_Depth;
        Mesh m_FullscreenMesh;

        public StencilSplatPass(RenderPassEvent evt, Material material)
        {
            renderPassEvent = evt;
            m_StencilSplatMaterial = material;
            useNativeRenderPass = false;
        }

        public void Setup(RTHandle depth)
        {
            m_Depth = depth;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
#if UNITY_EDITOR
            if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Direct3D11)
                ConfigureTarget(m_Depth, m_Depth);
            else
#endif
                ConfigureTarget(m_Depth);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_StencilSplatMaterial == null)
                return;

            var cmd = renderingData.commandBuffer;

            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.StencilSplat)))
            {
                m_StencilSplatMaterial.SetFloat(k_StencilRef, (float)StencilUsage.MaterialSimpleLit);
                m_StencilSplatMaterial.SetFloat(k_StencilReadMask, (float)StencilUsage.MaterialMask);
                m_StencilSplatMaterial.SetFloat(k_StencilWriteMask, (float)StencilUsage.MaterialMask);
                CoreUtils.DrawFullScreen(cmd, m_StencilSplatMaterial);
            }
        }

        public void Dispose()
        {

        }
    }
}
#endif
