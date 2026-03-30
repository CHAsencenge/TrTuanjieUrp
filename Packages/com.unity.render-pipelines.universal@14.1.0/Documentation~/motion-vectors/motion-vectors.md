URP 中的运动矢量
=====================================

URP 通过 [motion vector render pass](motion-vectors-sample.md) 计算表面片元在帧间的屏幕空间运动。URP 将运动数据存储在全屏纹理中，每个像素存储的值称为 [运动矢量（motion vectors）](#definition)。

Tuanjie 仅在帧中存在请求运动矢量渲染通道的活动功能时运行该通道。例如，以下 URP 功能请求运动矢量通道：[temporal anti-aliasing](../anti-aliasing.md#taa) 和 [motion blur](../Post-Processing-Motion-Blur.md)。有关如何在自定义通道中请求运动矢量通道的信息，请参阅 [Using the motion vector texture in your passes](motion-vectors-sample.md)。

错误或缺失的运动矢量可能会导致依赖它们的效果出现 [视觉伪影](motion-vectors-troubleshooting.md)。请按照本页的说明确保对象渲染器、材质和 **shaders** 正确设置以支持运动矢量。

URP 仅支持不透明材质（包括 alpha 剪切材质）的运动矢量，不支持透明材质的运动矢量。

实现细节
----------------------

本节介绍 URP 如何实现运动矢量。

### Motion vector 定义 <a name="definition"></a>

运动矢量是一个 2D 矢量，表示表面片元相对于 **camera** 自上一帧以来的运动，并投影到相机的 **clipping plane**。运动矢量纹理使用两个通道（R 和 G），每个 texel 存储可见表面片元的 UV 偏移量。如果从当前 UV 坐标中减去给定 texel 的运动矢量，则可以得到该 texel 在上一帧屏幕上的 UV 坐标。计算出的上一帧 UV 坐标可能超出屏幕边界。

### Object motion vectors and camera-only motion vectors

运动矢量分为两类：

*   **相机运动矢量（Camera motion vectors）**：仅由相机自身运动引起的运动矢量。
*   **对象运动矢量（Object motion vectors）**：由相机运动和片元所属对象的世界空间运动共同引起的运动矢量。

仅凭运动矢量纹理无法判断片元的屏幕运动是仅由相机运动引起，还是仅由对象运动引起，亦或是两者的组合。

计算相机运动矢量仅需单次全屏通道，该通道的每帧计算负载与 **scene** 复杂度无关。只需知道屏幕上所有 **pixels** 的当前 3D 位置及相机的运动方式，这些信息可以从 **depth buffer** 以及当前帧和上一帧的相机矩阵推导得出。

对象运动矢量的计算负载取决于场景中移动对象的数量和复杂度，因为需要针对每个对象进行绘制，以计算其运动。每次绘制还需要应用相机的运动贡献。

### 渲染每个物体运动矢量时的情况 <a name="cases-when-motion-vectors"></a>

Tuanjie 在以下三个条件均满足时，为 **mesh** 渲染对象运动矢量：

1.  与 mesh 关联的 shader 在其活动的 SubShader 块中包含 [MotionVectors pass](motion-vectors-shader-support.md), 或者使用默认的motion vector pass。
    
2.  该 mesh 通过以下任一渲染器进行渲染：
    1.  **MeshRenderer**，且其 **Motion Vectors** 属性未设置为 `Camera Motion Only`。
    2.  使用以下 API：[Graphics.RenderMesh](https://docs.unity.cn/cn/tuanjiemanual/ScriptReference/Graphics.RenderMesh.html)、[Graphics.RenderMeshInstanced](https://docs.unity.cn/cn/tuanjiemanual/ScriptReference/Graphics.RenderMeshInstanced.html) 或 [Graphics.RenderMeshIndirect](https://docs.unity.cn/cn/tuanjiemanual/ScriptReference/Graphics.RenderMeshIndirect.html)，且 `RenderParams` 结构体的 `MotionVectorMode` 成员未设置为 `Camera`。
