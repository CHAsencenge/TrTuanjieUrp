//
//  UnityNativePluginWrapper.cpp
//  MetalUpscaling
//
//  Created by jadiek on 2025/6/17.
//
#import <Metal/Metal.h>

#include "PlatformBase.h"
#include "UnityPluginHeaders/IUnityInterface.h"
#include "UnityPluginHeaders/IUnityGraphics.h"
#include "UnityPluginHeaders/IUnityGraphicsMetal.h"
#include "MTLUtils.h"
//#include "MetalUpscaling-Swift.h"



#if SUPPORT_METAL
////for UNITY_IOS
#import "UnityAppController.h"
@interface MyAppController : UnityAppController
{
}
- (void)shouldAttachRenderDelegate;
@end
@implementation MyAppController
- (void)shouldAttachRenderDelegate
{
   UnityRegisterRenderingPluginV5(&UnityPluginLoad, &UnityPluginUnload);
}

@end
IMPL_APP_CONTROLLER_SUBCLASS(MyAppController);

static IUnityInterfaces* s_UnityInterfaces = NULL;
static IUnityGraphicsMetal* s_MetalGraphics = NULL;

static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType)
{
    if (eventType == kUnityGfxDeviceEventInitialize)
    {
        s_MetalGraphics = s_UnityInterfaces->Get<IUnityGraphicsMetal>();
    }
}

static void EnsureMetalGraphics()
{
    if(s_MetalGraphics == nullptr)
    {
        s_MetalGraphics = s_UnityInterfaces->Get<IUnityGraphicsMetal>();
    }
}

extern "C" bool IsSupport()
{
    EnsureMetalGraphics();
    return [MTLUtils isSupport:s_MetalGraphics->MetalDevice()];
}

extern "C" void EndEncoder()
{
    s_MetalGraphics->EndCurrentCommandEncoder();
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces)
{
    s_UnityInterfaces = unityInterfaces;
    s_UnityInterfaces->Get<IUnityGraphics>()->RegisterDeviceEventCallback(OnGraphicsDeviceEvent);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload()
{
    
}

extern "C" bool BuildMetalFXSpatialScaler(id<MTLTexture> srcTexture, id<MTLTexture> dstTexture, int processingMode)
{
    if(@available(macos 13.0, ios 16.0, *))
    {
        EnsureMetalGraphics();
        return [MTLUtils buildSpatialScaler:srcTexture dstTexture:dstTexture processingMode:processingMode device:s_MetalGraphics->MetalDevice()];
    }
    return false;
}

extern "C" bool BuildMetalFXTemporalScaler(id<MTLTexture> srcTexture, id<MTLTexture> dstTexture, id<MTLTexture> depthTexutre, id<MTLTexture> motionTexture)
{
    if(@available(macos 13.0, ios 16.0, *))
    {
        EnsureMetalGraphics();
        return [MTLUtils buildTemporalScaler:srcTexture dstTexture:dstTexture depthTexture:depthTexutre motionTexture:motionTexture device:s_MetalGraphics->MetalDevice()];
    }
    return false;
    
}

extern "C" bool PerformMetalFXSpatialUpscaling(id<MTLTexture> srcTexture, id<MTLTexture> dstTexture)
{
    if(@available(macos 13.0, ios 16.0, *))
    {
        EnsureMetalGraphics();
        s_MetalGraphics->EndCurrentCommandEncoder();
        return [MTLUtils callSpatialScaling:srcTexture dstTexture:dstTexture commandBuffer:s_MetalGraphics->CurrentCommandBuffer()];
    }
    return false;
        
    
}

extern "C" bool PerformMetalFXTemporalUpscaling(id<MTLTexture> srcTexture, id<MTLTexture> dstTexture, id<MTLTexture> depthTexutre, id<MTLTexture> motionTexture, float jitterOffsetX, float jitterOffsetY, bool reset)
{
    if(@available(macos 13.0, ios 16.0, *))
    {
        EnsureMetalGraphics();
        s_MetalGraphics->EndCurrentCommandEncoder();
        return [MTLUtils callTemporalScaling:srcTexture dstTexture:dstTexture depthTexture:depthTexutre motionTexture:motionTexture jitterOffsetX:jitterOffsetX jitterOffsetY:jitterOffsetY reset:reset commandBuffer:s_MetalGraphics->CurrentCommandBuffer()];
    }
    return false;
}


#endif
