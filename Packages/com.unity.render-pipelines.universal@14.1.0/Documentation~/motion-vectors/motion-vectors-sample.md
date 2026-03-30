着色器中的示例运动矢量
========================================

任何 `ScriptableRenderPass` 实现都可以请求运动矢量纹理作为输入。要实现此功能，请在自定义 Renderer Feature 的 [AddRenderPasses](https://docs.unity.cn/cn/Packages-cn/com.unity.render-pipelines.universal@latest/api/UnityEngine.Rendering.Universal.ScriptableRendererFeature.html#UnityEngine_Rendering_Universal_ScriptableRendererFeature_AddRenderPasses_UnityEngine_Rendering_Universal_ScriptableRenderer_UnityEngine_Rendering_Universal_RenderingData__) 回调中，在 [ScriptableRenderPass.ConfigureInput](https://docs.unity.cn/cn/Packages-cn/com.unity.render-pipelines.universal@latest/api/UnityEngine.Rendering.Universal.ScriptableRenderPass.html#UnityEngine_Rendering_Universal_ScriptableRenderPass_ConfigureInput_UnityEngine_Rendering_Universal_ScriptableRenderPassInput_) 方法中添加 `ScriptableRenderPassInput.Motion` 标志。如果该帧中没有其他效果使用运动矢量，设置此输入标志将强制 URP 渲染器在帧中注入运动矢量渲染通道。

要在 **shader** pass 中采样运动矢量纹理，请在 `HLSLPROGRAM` 部分声明 shader 资源：

```
TEXTURE2D_X(_MotionVectorTexture);     
SAMPLER(sampler_MotionVectorTexture);
```

执行采样时，使用以下宏：

```
SAMPLE_TEXTURE2D_X(_MotionVectorTexture, sampler_MotionVectorTexture, uv);
```

后缀 `_X` 确保在 **XR** 平台上正确声明和采样该纹理。
