using System;
using UnityEngine;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine.Experimental.Rendering.RenderGraphModule;

#if UNITY_GPU_DRIVEN_PIPELINE
namespace UnityEngine.Rendering.Universal.Internal
{
    public class GPUReflectionProbePass : ScriptableRenderPass
    {
        private GraphicsBuffer m_ReflectionProbeInfoBuffer;
        private GraphicsBuffer m_ReflectionProbeCullArgsBuffer;
        private ComputeShader m_ReflectionProbeCullCS;
        private GPUReflectionProbeInfo[] m_ReflectionProbeInfoArray;
        private ReflectionProbeAtlas m_ReflectionProbeAtlas;
        private LocalKeyword m_ReflectionProbePresent;
        private int m_ActiveReflectionProbeCount;


        private static readonly int s_ReflectionProbeInfoBufferName = Shader.PropertyToID("_ReflectionProbeInfoBuffer");
        private static readonly int s_ReflectionProbeCullArgsBufferName = Shader.PropertyToID("_ReflectionProbeCullArgsBuffer");
        private static readonly int s_ActiveReflectionProbeCount = Shader.PropertyToID("_ActiveReflectionProbeCount");
        private static readonly int s_PackDataImportanceBits = 30;
        private static readonly int s_PackDataTextureValidBits = 1;
        private static readonly string s_KernelNameInitReflectionProbeCull = "InitReflectionProbeCull";
        private static readonly string s_KernelNameReflectionProbeCull = "ReflectionProbeCull";
        private static readonly string s_KeywordNameReflectionProbePresent = "_REFLECTION_PROBE_PRESENT";
        

        public GPUReflectionProbePass(RenderPassEvent evt, ComputeShader reflectionProbeCullCS)
        {
            base.profilingSampler = new ProfilingSampler(nameof(GPUReflectionProbePass));
            base.renderPassEvent = evt;
            base.useNativeRenderPass = false;
            m_ReflectionProbeCullCS = reflectionProbeCullCS;
            m_ReflectionProbeAtlas = new ReflectionProbeAtlas();
            if (reflectionProbeCullCS != null)
            {
                m_ReflectionProbePresent = reflectionProbeCullCS.keywordSpace.FindKeyword(s_KeywordNameReflectionProbePresent);
            }
        }

        public void Setup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            CreateReflectionProbeCullArgsBuffer();
            CreateReflectionProbeCullBuffer();
            m_ActiveReflectionProbeCount = Math.Min(renderingData.cullResults.activeReflectionProbes.Length, UniversalRenderPipeline.maxVisibleReflectionProbes);
            if (m_ActiveReflectionProbeCount > 0)
            {
                m_ReflectionProbeAtlas.Init(UniversalRenderPipeline.asset.reflectionProbeAtlasResolution);
            }
        }

        public void SetupLights(ref RenderingData renderingData)
        {
            using (new ProfilingScope(renderingData.commandBuffer, ProfilingSampler.Get(URPProfileId.ReflectionProbeAtlas)))
            {
                if (m_ReflectionProbeAtlas.IsInitialized())
                {
                    m_ReflectionProbeAtlas.NewRender();
                    m_ReflectionProbeAtlas.ProcessVisibleReflectionProbes(renderingData.commandBuffer, renderingData.cullResults);
                }
            }
        }

        private void CreateReflectionProbeCullBuffer()
        {
            if (m_ReflectionProbeInfoBuffer == null)
            {
                int count = UniversalRenderPipeline.maxVisibleReflectionProbes;

                m_ReflectionProbeInfoBuffer = new GraphicsBuffer(
                    GraphicsBuffer.Target.Structured,
                    count,
                    UnsafeUtility.SizeOf(typeof(GPUReflectionProbeInfo)));

                m_ReflectionProbeInfoBuffer.name = "ReflectionProbeInfoBuffer";

                m_ReflectionProbeInfoArray = new GPUReflectionProbeInfo[count];
            }
        }

        private void CreateReflectionProbeCullArgsBuffer()
        {
            if (m_ReflectionProbeCullArgsBuffer == null)
            {
                m_ReflectionProbeCullArgsBuffer = new GraphicsBuffer(
                    GraphicsBuffer.Target.IndirectArguments,
                    4,
                    sizeof(uint));

                m_ReflectionProbeCullArgsBuffer.name = "ReflectionProbeCullArgsBuffer";
            }
        }

        private void UploadReflectionProbeInfo(CommandBuffer cmd, CullingResults cullResults)
        {
            for (int i = 0; i < m_ActiveReflectionProbeCount; ++i)
            {
                var reflectionProbeInfo = cullResults.activeReflectionProbes[i];
                m_ReflectionProbeInfoArray[i].renderingLayerMask = (uint)reflectionProbeInfo.reflectionProbe.renderingLayerMask;
                uint boxProjection_TextureValid_Importance = reflectionProbeInfo.reflectionProbe.boxProjection ? (1u << (s_PackDataImportanceBits + s_PackDataTextureValidBits)) : 0u;
                boxProjection_TextureValid_Importance |= (reflectionProbeInfo.texture != null) ? (1u << (s_PackDataImportanceBits)) : 0u;
                boxProjection_TextureValid_Importance |= ((uint)reflectionProbeInfo.importance & ((1u << s_PackDataImportanceBits) - 1));
                m_ReflectionProbeInfoArray[i].boxProjection_TextureValid_Importance = boxProjection_TextureValid_Importance;
                m_ReflectionProbeInfoArray[i].blendDistance = reflectionProbeInfo.blendDistance;
                m_ReflectionProbeInfoArray[i].boxMin = reflectionProbeInfo.bounds.min;
                m_ReflectionProbeInfoArray[i].boxMax = reflectionProbeInfo.bounds.max;
                m_ReflectionProbeInfoArray[i].probePosition = reflectionProbeInfo.localToWorldMatrix.GetPosition();
                m_ReflectionProbeInfoArray[i].scaleOffset = m_ReflectionProbeAtlas.m_ScaleOffset[i];
            }

            m_ReflectionProbeInfoBuffer.SetData(m_ReflectionProbeInfoArray, 0, 0, m_ActiveReflectionProbeCount);
            cmd.SetGlobalBuffer(s_ReflectionProbeInfoBufferName, m_ReflectionProbeInfoBuffer);
        }


        public void Dispose()
        {
            m_ReflectionProbeInfoBuffer?.Dispose();
            m_ReflectionProbeCullArgsBuffer?.Dispose();
            m_ReflectionProbeAtlas?.Dispose();
        }

        private void BindNativeBufferInitKernel(CommandBuffer cmd, int kernelIndex)
        {
            GPUDriven.Manager.BindVisibleInstanceBuffer(cmd, m_ReflectionProbeCullCS, kernelIndex);
        }

        private void BindNativeBufferCullKernel(CommandBuffer cmd, int kernelIndex)
        {
            GPUDriven.Manager.BindVisibleInstanceBuffer(cmd, m_ReflectionProbeCullCS, kernelIndex);
            GPUDriven.Manager.BindInstanceHeaderBuffer(cmd, m_ReflectionProbeCullCS, kernelIndex);
            GPUDriven.Manager.BindRWInstanceSubsetBuffer(cmd, m_ReflectionProbeCullCS, kernelIndex);
        }

        private void ExecuteReflectionProbeCulling(ScriptableRenderContext context, CommandBuffer cmd)
        {
            int initKernelIndex = m_ReflectionProbeCullCS.FindKernel(s_KernelNameInitReflectionProbeCull);
            BindNativeBufferInitKernel(cmd, initKernelIndex);
            cmd.SetComputeBufferParam(m_ReflectionProbeCullCS, initKernelIndex, s_ReflectionProbeCullArgsBufferName, m_ReflectionProbeCullArgsBuffer);
            cmd.DispatchCompute(m_ReflectionProbeCullCS, initKernelIndex, 1, 1, 1);


            int cullKernelIndex = m_ReflectionProbeCullCS.FindKernel(s_KernelNameReflectionProbeCull);
            BindNativeBufferCullKernel(cmd, cullKernelIndex);
            if (m_ActiveReflectionProbeCount > 0)
            {
                cmd.SetKeyword(m_ReflectionProbeCullCS, m_ReflectionProbePresent, true);
                cmd.SetComputeIntParam(m_ReflectionProbeCullCS, s_ActiveReflectionProbeCount, m_ActiveReflectionProbeCount);
                cmd.SetComputeBufferParam(m_ReflectionProbeCullCS, cullKernelIndex, s_ReflectionProbeInfoBufferName, m_ReflectionProbeInfoBuffer);
            }
            else
            {
                cmd.SetKeyword(m_ReflectionProbeCullCS, m_ReflectionProbePresent, false);
            }
            cmd.DispatchCompute(m_ReflectionProbeCullCS, cullKernelIndex, m_ReflectionProbeCullArgsBuffer, 0);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }


        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = renderingData.commandBuffer;
            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.GPUReflectionProbeCull)))
            {
                UploadReflectionProbeInfo(cmd, renderingData.cullResults);
                if (m_ReflectionProbeAtlas.IsInitialized())
                {
                    ExecuteReflectionProbeCulling(context, cmd);
                }
            }
        }

        public struct GPUReflectionProbeInfo
        {
            public uint renderingLayerMask;
            public Vector3 boxMin;
            public uint boxProjection_TextureValid_Importance;
            public Vector3 boxMax;
            public float blendDistance;
            public Vector3 probePosition;
            public Vector4 scaleOffset;
        }

        private class PassData
        {
            internal ComputeShader reflectionProbeCullCS;
            internal GraphicsBuffer reflectionProbeInfoBuffer;
            internal GraphicsBuffer reflectionProbeCullArgsBuffer;
        }

        internal void Render(RenderGraph renderGraph, in TextureHandle depthTexture, ref RenderingData renderingData)
        {
            using (var builder = renderGraph.AddRenderPass<PassData>("Execute GPU Reflection Probe", out var passData, base.profilingSampler))
            {
                passData.reflectionProbeCullCS = m_ReflectionProbeCullCS;
                passData.reflectionProbeInfoBuffer = m_ReflectionProbeInfoBuffer;
                passData.reflectionProbeCullArgsBuffer = m_ReflectionProbeCullArgsBuffer;

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    ExecuteReflectionProbeCulling(context.renderContext, context.cmd);
                });

                return;
            }
        }
    }
}
#endif
