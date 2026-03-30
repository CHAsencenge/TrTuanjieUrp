运动矢量渲染通道
=================================

了解 **MotionVectors** 渲染通道如何渲染运动矢量纹理。

Location in the frame loop
--------------------------

URP 在 `BeforeRenderingPostProcessing` 事件中渲染运动矢量。在此事件之前，运动矢量纹理可能尚未设置，或可能仍包含上一帧的运动矢量数据。

MotionVectors pass structure
----------------------------

URP 以两个步骤渲染运动矢量纹理：

1.  URP 在 **MotionVectors** 全屏通道中渲染 **camera** 运动矢量。该通道使用当前帧和上一帧的深度纹理和相机矩阵计算相机运动矢量。该通道的计算负载固定于每个相机，无需渲染器或材质提供特殊的运动矢量支持。
2.  URP 为 [每个支持运动矢量的渲染器和材质组合](motion-vectors.md#cases-when-motion-vectors) 绘制对象运动矢量 **shader** 通道。
