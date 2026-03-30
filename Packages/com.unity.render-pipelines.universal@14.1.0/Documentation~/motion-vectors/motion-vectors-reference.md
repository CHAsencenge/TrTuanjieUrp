MeshRenderer 组件窗口参考中的运动矢量设置
=========================================

要指定 **GameObject** 在运动矢量缓冲区中的贡献方式，请使用 **Motion Vectors** 属性：**Mesh Renderer** >> **Additional Settings** >> **Motion Vectors**。该属性允许你禁用特定对象的运动矢量渲染，或者在对象渲染器的可见片元上用零填充运动矢量纹理。

下表描述了 **Motion Vectors** 属性的可用选项。

| **Motion Vectors** 选项 | 描述 |
| --- | --- |
| **Camera Motion Only** | Tuanjie 在渲染相机运动矢量时，将该对象视为静止的。Tuanjie 不会为此 **MeshRenderer** 绘制对象运动矢量 pass。如果运动矢量渲染成为 GPU 瓶颈，你可以为移动缓慢的对象使用此选项作为优化措施。 |
| **Per Object Motion** | Tuanjie 为该对象渲染单独的 **Motion Vectors** pass。 |
| **Force No Motion** | Tuanjie 每帧为该对象渲染 **Motion Vectors** pass，但设置一个特殊的 shader 统一变量，使该 pass 跳过计算并写入零值。仍然需要单独的对象 pass 以覆盖全屏 pass 中的非零相机运动矢量。  <br>此选项可用于避免相机运动模糊在 3D HUD、第三人称角色、赛车等对象上的伪影，或者用于消除因错误的运动矢量导致的其他伪影。 |
