输出运动矢量纹理
========================================================

在目前的 Tuanjie 版本中，URP 会自动为所有未包含 MotionVectors LightMode 标签的 SubShader 块使用回退 pass，这一特性在 Tuanjie 1.6.0 中仍然会保留。
如果您想为 alpha 剪切、LOD 淡入淡出等效果提供支持，可以自行在ShaderLab shader 渲染 MotionVectors pass，具体方式如下：
在实际使用的 SubShader 包含以下 [LightMode 标签](../urp-shaders/urp-shaderlab-pass-tags.md#lightmode) 的 pass：

```
Tags { "LightMode" = "MotionVectors" }
```

例如：

```
Shader "Example/MyCustomShaderWithPerObjectMotionVectors" {     
    SubShader {         
        // ...其他 passes、SubShader 标签和命令          
        Pass {             
            Tags { "LightMode" = "MotionVectors" }             
            ColorMask RG                          
            HLSLPROGRAM                          
            // 在此处编写您的 shader 代码                          
            ENDHLSL         
        }     
    } 
}
```
