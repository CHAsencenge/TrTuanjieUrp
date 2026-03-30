using UnityEngine;
using UnityEngine.Rendering;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// This class holds VG Shadow data that persists over a frame and
    /// is included in UniversalAdditionalCameraData.
    /// </summary>
    internal sealed class VGShadowData
    {
        internal RTHandle hizRT = null;

        // The size must be consistent with k_MaxCascades in MainLightShadowCasterPass
        internal Matrix4x4[] preViewMatrices = new Matrix4x4[4];

        internal Matrix4x4[] preProjMatrices = new Matrix4x4[4];
    }

#if UNITY_EDITOR
    /// <summary>
    /// UniversalAdditionalCameraData is not included in scene camera,
    /// so we add a component for scene camera.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(Camera))]
    internal sealed class VGShadowDataController : MonoBehaviour
    {
        internal RTHandle hizRT = null;

        // The size must be consistent with k_MaxCascades in MainLightShadowCasterPass
        internal Matrix4x4[] preViewMatrices = new Matrix4x4[4];

        internal Matrix4x4[] preProjMatrices = new Matrix4x4[4];
    }
#endif
}
