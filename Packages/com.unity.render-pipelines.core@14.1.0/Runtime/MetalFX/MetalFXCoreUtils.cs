using System;
using System.Runtime.InteropServices;
using AOT;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine.Experimental.Rendering;

namespace UnityEngine.Rendering
{
    /// <summary>
    /// Core utility functions for Apple MetalFX upscaling
    /// </summary>
    public static class MetalFXCoreUtils
    {
        /// <summary>
        /// Checks if MetalFX upscaling is supported on the current platform
        /// </summary>
        /// <returns>True if MetalFX is supported, false otherwise</returns>
        public static bool IsSupported()
        {
            return MetalFXNativeWrapper.NativeIsSupport();
        }

        /// <summary>
        /// Performs MetalFX spatial upscaling
        /// </summary>
        public static void PerformMetalFXSpatialUpscaling(CommandBuffer cmd, RTHandle srcHandle, RTHandle dstHandle, Camera camera = null)
        {
            MetalFXNativeWrapper.PerformMetalFXSpatialUpscaling(cmd, srcHandle, dstHandle, camera);
        }

        /// <summary>
        /// Performs MetalFX TAAU
        /// </summary>
        public static void PerformMetalFXTemporalUpscaling(CommandBuffer cmd, RTHandle srcHandle, RTHandle dstHandle, RTHandle depth, RTHandle motion, float jitterOffsetX, float jitterOffsetY, bool reset)
        {
            MetalFXNativeWrapper.PerformMetalFXTemporalUpscaling(cmd, srcHandle, dstHandle, depth, motion, jitterOffsetX, jitterOffsetY, reset);
        }
    }

    internal static class MetalFXNativeWrapper
    {
        public const int ProcessingModePerceptual = 0;
        public const int ProcessingModeLinear = 1;
        public const int ProcessingModeHDR = 2;

        #region NativeInterface
#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX
        private const string _dllName = "MetalUpscalingOSX";
#elif UNITY_IOS
        private const string _dllName = "__Internal";
#endif

#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX || UNITY_IOS
        [DllImport(_dllName, EntryPoint = "BuildMetalFXSpatialScaler")]
        private static extern bool NativeBuildMetalFXSpatialScaler(IntPtr src, IntPtr dest, int mode);
#else
        private static bool NativeBuildMetalFXSpatialScaler(IntPtr src, IntPtr dest, int mode) { return false; }
#endif

#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX || UNITY_IOS
        [DllImport(_dllName, EntryPoint = "BuildMetalFXTemporalScaler")]
        private static extern bool NativeBuildMetalFXTemporalScaler(IntPtr src, IntPtr dest, IntPtr depth, IntPtr motion);
#else
        private static bool NativeBuildMetalFXTemporalScaler(IntPtr src, IntPtr dest, IntPtr depth, IntPtr motion) { return false;}
#endif


#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX || UNITY_IOS
        [DllImport(_dllName, EntryPoint = "PerformMetalFXSpatialUpscaling")]
        private static extern bool NativePerformMetalFXSpatialUpscaling(IntPtr src, IntPtr dest);
#else
        private static bool NativePerformMetalFXSpatialUpscaling(IntPtr src, IntPtr dest) { return false; }
#endif

#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX || UNITY_IOS
        [DllImport(_dllName, EntryPoint = "PerformMetalFXTemporalUpscaling")]
        private static extern bool NativePerformMetalFXTemporalUpscaling(IntPtr src, IntPtr dest, IntPtr depth, IntPtr motion, float jitterOffsetX, float jitterOffsetY, bool reset);
#else
        private static bool NativePerformMetalFXTemporalUpscaling(IntPtr src, IntPtr dest, IntPtr depth, IntPtr motion, float jitterOffsetX, float jitterOffsetY, bool reset) { return false; }
#endif

#if UNITY_STANDALONE_OSX || UNITY_EDITOR_OSX || UNITY_IOS
        [DllImport(_dllName, EntryPoint = "IsSupport")]
        public static extern bool NativeIsSupport();
#else
        public static bool NativeIsSupport() { return false; }
#endif
        #endregion

        private struct ScalerId
        {
            public int SrcInstanceID;
            public int DstInstanceID;
            public int SrcWidth;
            public int SrcHeight;
            public int DstWidth;
            public int DstHeight;
            public GraphicsFormat SrcFormat;
            public GraphicsFormat DstFormat;

            public GraphicsFormat DepthFormat;
            public GraphicsFormat MotionFormat;


            public bool IsEqual(ScalerId other)
            {
                return (SrcInstanceID == other.SrcInstanceID && DstInstanceID == other.DstInstanceID && DepthFormat == other.DepthFormat && MotionFormat == other.MotionFormat)
                       || (SrcWidth == other.SrcWidth && SrcHeight == other.SrcHeight && DstWidth == other.DstWidth && DstHeight == other.DstHeight && SrcFormat == other.SrcFormat && DstFormat == other.DstFormat);
            }
        }

        private static ScalerId _spatialId = new ScalerId();
        private static ScalerId _temporalId = new ScalerId();

        private static bool UpdateSpatialUpscaler(RTHandle srcHandle, RTHandle dstHandle)
        {
            ScalerId newId = new ScalerId()
            {
                SrcInstanceID = srcHandle.GetInstanceID(),
                DstInstanceID = dstHandle.GetInstanceID(),
                SrcWidth = srcHandle.rt.width,
                SrcHeight = srcHandle.rt.height,
                DstWidth = dstHandle.rt.width,
                DstHeight = dstHandle.rt.height,
                SrcFormat = srcHandle.rt.graphicsFormat,
                DstFormat = dstHandle.rt.graphicsFormat
            };
            if (!_spatialId.IsEqual(newId))
            {
                _spatialId = newId;
                return true;
            }

            return false;
        }

        private static bool UpdateTemporalUpscaler(RTHandle srcHandle, RTHandle dstHandle, RTHandle depth, RTHandle motion)
        {
            ScalerId newId = new ScalerId()
            {
                SrcInstanceID = srcHandle.GetInstanceID(),
                DstInstanceID = dstHandle.GetInstanceID(),
                SrcWidth = srcHandle.rt.width,
                SrcHeight = srcHandle.rt.height,
                DstWidth = dstHandle.rt.width,
                DstHeight = dstHandle.rt.height,
                SrcFormat = srcHandle.rt.graphicsFormat,
                DstFormat = dstHandle.rt.graphicsFormat,

                DepthFormat = depth.rt.graphicsFormat,
                MotionFormat = motion.rt.graphicsFormat
            };
            if (!_temporalId.IsEqual(newId))
            {
                _temporalId = newId;
                return true;
            }

            return false;
        }

        private const int EventIDBuildSpatial = 50001;
        private const int EventIDPerformSpatial = 50002;
        private const int EventIDBuildTemporal = 50003;
        private const int EventIDPerformTemporal = 50004;

        private struct UpscalingParam
        {
            public IntPtr SrcHandle;
            public IntPtr DstHandle;
            public IntPtr DepthHandle;
            public IntPtr MotionHandle;
            public float JitterOffsetX;
            public float JitterOffsetY;

            public int Mode;
            public bool Reset;
        }
        private delegate void CallbackDelegate(int eventId, IntPtr data);

        private static readonly IntPtr CallbackDelegateFuncPtr = Marshal.GetFunctionPointerForDelegate(new CallbackDelegate(DoPerformMetalFXUpscaling));
        public static unsafe void PerformMetalFXSpatialUpscaling(CommandBuffer cmd, RTHandle srcHandle, RTHandle dstHandle, Camera camera = null)
        {
            if (UpdateSpatialUpscaler(srcHandle, dstHandle))
            {
                cmd.IssuePluginEventAndData(CallbackDelegateFuncPtr, EventIDBuildSpatial, GenerateParamPtr(srcHandle, dstHandle, camera));
            }
            cmd.IssuePluginEventAndData(CallbackDelegateFuncPtr, EventIDPerformSpatial, GenerateParamPtr(srcHandle, dstHandle, camera));
            // {
            //     NativeBuildMetalFXSpatialScaler(srcHandle.rt.GetNativeTexturePtr(), dstHandle.rt.GetNativeTexturePtr(), GetMode(dstHandle.rt, camera));
            // }
            // NativePerformMetalFXSpatialUpscaling(srcHandle.rt.GetNativeTexturePtr(), dstHandle.rt.GetNativeTexturePtr());
        }

        public static void PerformMetalFXTemporalUpscaling(CommandBuffer cmd, RTHandle srcHandle, RTHandle dstHandle, RTHandle depth, RTHandle motion, float jitterOffsetX, float jitterOffsetY, bool reset)
        {
            if (UpdateTemporalUpscaler(srcHandle, dstHandle, depth, motion))
            {
                cmd.IssuePluginEventAndData(CallbackDelegateFuncPtr, EventIDBuildTemporal, GenerateParamPtr(srcHandle, dstHandle, depth, motion, jitterOffsetX, jitterOffsetY, reset));
                // NativeBuildMetalFXTemporalScaler(srcHandle.rt.GetNativeTexturePtr(), dstHandle.rt.GetNativeTexturePtr(), depth.rt.GetNativeDepthBufferPtr(), motion.rt.GetNativeTexturePtr());
            }
            cmd.IssuePluginEventAndData(CallbackDelegateFuncPtr, EventIDPerformTemporal, GenerateParamPtr(srcHandle, dstHandle, depth, motion, jitterOffsetX, jitterOffsetY, reset));
            // NativePerformMetalFXTemporalUpscaling(srcHandle.rt.GetNativeTexturePtr(), dstHandle.rt.GetNativeTexturePtr(), depth.rt.GetNativeDepthBufferPtr(), motion.rt.GetNativeTexturePtr(), jitterOffsetX, jitterOffsetY, reset);
        }

        private static unsafe IntPtr GenerateParamPtr(RTHandle srcHandle, RTHandle dstHandle, Camera camera)
        {
            IntPtr paramPtr = Marshal.AllocHGlobal(sizeof(UpscalingParam));
            var nativePtr = (UpscalingParam*)paramPtr.ToPointer();
            nativePtr->SrcHandle = srcHandle.rt.GetNativeTexturePtr();
            nativePtr->DstHandle = dstHandle.rt.GetNativeTexturePtr();
            nativePtr->Mode = GetMode(dstHandle.rt, camera);
            return paramPtr;
        }

        private static unsafe IntPtr GenerateParamPtr(RTHandle srcHandle, RTHandle dstHandle, RTHandle depth, RTHandle motion, float jitterOffsetX, float jitterOffsetY, bool reset)
        {
            IntPtr paramPtr = Marshal.AllocHGlobal(sizeof(UpscalingParam));
            var nativePtr = (UpscalingParam*)paramPtr.ToPointer();
            nativePtr->SrcHandle = srcHandle.rt.GetNativeTexturePtr();
            nativePtr->DstHandle = dstHandle.rt.GetNativeTexturePtr();
            nativePtr->DepthHandle = depth.rt.GetNativeTexturePtr();
            nativePtr->MotionHandle = motion.rt.GetNativeTexturePtr();
            nativePtr->JitterOffsetX = jitterOffsetX;
            nativePtr->JitterOffsetY = jitterOffsetY;
            nativePtr->Reset = reset;
            return paramPtr;
        }

        [MonoPInvokeCallback(typeof(CallbackDelegate))]
        private static unsafe void DoPerformMetalFXUpscaling(int eventId, IntPtr data)
        {
            UpscalingParam* param = (UpscalingParam*)data.ToPointer();
            switch (eventId)
            {
                case EventIDBuildSpatial:
                {
                    if (!NativeBuildMetalFXSpatialScaler(param->SrcHandle, param->DstHandle, param->Mode))
                        Debug.LogError("[MetalFX] Native failed to build spatial scaler");
                    break;
                }
                case EventIDBuildTemporal:
                {
                    if (!NativeBuildMetalFXTemporalScaler(param->SrcHandle, param->DstHandle, param->DepthHandle, param->MotionHandle))
                        Debug.LogError("[MetalFX] Native failed to build temporal scaler");
                    break;
                }
                case EventIDPerformSpatial:
                {
                    if (!NativePerformMetalFXSpatialUpscaling(param->SrcHandle, param->DstHandle))
                        Debug.LogError("[MetalFX] Native failed to perform spatial upscaling");
                    break;
                }
                case EventIDPerformTemporal:
                {
                    if (!NativePerformMetalFXTemporalUpscaling(param->SrcHandle, param->DstHandle, param->DepthHandle, param->MotionHandle, param->JitterOffsetX, param->JitterOffsetY, param->Reset))
                        Debug.LogError("[MetalFX] Native failed to perform temporal upscaling");
                    break;
                }
            }
            Marshal.FreeHGlobal(data);
        }

        private static int GetMode(RenderTexture output, Camera camera = null)
        {
            if (camera == null)
            {
                camera = Camera.main;
            }
            if (output.sRGB)
            {
                return ProcessingModePerceptual;
            }

            if (camera != null && camera.allowHDR)
            {
                return ProcessingModeHDR;
            }

            return ProcessingModeLinear;
        }
    }
}
