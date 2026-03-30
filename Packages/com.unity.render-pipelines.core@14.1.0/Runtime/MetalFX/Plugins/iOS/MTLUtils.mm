
#import <Metal/Metal.h>

#import "MTLUtils.h"

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
    #ifdef __IPHONE_16_0 
        #if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_16_0
            #define ENABLE_METALFX 
        #endif
    #endif
#endif

#ifdef ENABLE_METALFX
#import <MetalFX/MetalFX.h>
#endif

@implementation MTLUtils

#ifdef ENABLE_METALFX

static id<MTLFXTemporalScaler> _mfxTemporalScaler = nil;
static id<MTLFXSpatialScaler> _mfxSpatialScaler = nil;

+ (BOOL)buildSpatialScaler:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture processingMode:(int)processingMode device:(id<MTLDevice>)device {
    _mfxSpatialScaler = nil;
    MTLFXSpatialScalerDescriptor* desc = [MTLFXSpatialScalerDescriptor new];
    desc.inputWidth = srcTexture.width;
    desc.inputHeight = srcTexture.height;
    desc.outputWidth = dstTexture.width;
    desc.outputHeight = dstTexture.height;
    desc.colorTextureFormat = srcTexture.pixelFormat;
    desc.outputTextureFormat = dstTexture.pixelFormat;
    desc.colorProcessingMode = (MTLFXSpatialScalerColorProcessingMode)processingMode;
    
    _mfxSpatialScaler = [desc newSpatialScalerWithDevice:device];
    if(!_mfxSpatialScaler){
        NSLog(@"The spatial scaler effect is not usable");
        return NO;
    }
    return YES;
}

+ (BOOL)buildTemporalScaler:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture depthTexture:(id<MTLTexture>)depthTexture motionTexture:(id<MTLTexture>)motionTexture device:(id<MTLDevice>)device {
    _mfxTemporalScaler = nil;
    MTLFXTemporalScalerDescriptor* desc = [MTLFXTemporalScalerDescriptor new];
    desc.inputWidth = srcTexture.width;
    desc.inputHeight = srcTexture.height;
    desc.outputWidth = dstTexture.width;
    desc.outputHeight = dstTexture.height;
    desc.colorTextureFormat = srcTexture.pixelFormat;
    desc.outputTextureFormat = dstTexture.pixelFormat;
    desc.depthTextureFormat = depthTexture.pixelFormat;
    desc.motionTextureFormat = motionTexture.pixelFormat;
    
    _mfxTemporalScaler = [desc newTemporalScalerWithDevice:device];
    if (!_mfxTemporalScaler) {
        NSLog(@"The temporal scaler effect is not usable");
        return NO;
    }
    
    _mfxTemporalScaler.motionVectorScaleX = -(float)srcTexture.width;
    _mfxTemporalScaler.motionVectorScaleY = -(float)srcTexture.height;
    return YES;
}

+ (BOOL)callSpatialScaling:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
        
    if (!_mfxSpatialScaler) {
        NSLog(@"Spatial scaler not initialized");
        return NO;
    }
    
    _mfxSpatialScaler.colorTexture = srcTexture;
    _mfxSpatialScaler.outputTexture = dstTexture;
    
    [_mfxSpatialScaler encodeToCommandBuffer:commandBuffer];
    return YES;
}

+ (BOOL)callTemporalScaling:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture depthTexture:(id<MTLTexture>)depthTexture motionTexture:(id<MTLTexture>)motionTexture jitterOffsetX:(float)jitterOffsetX jitterOffsetY:(float)jitterOffsetY reset:(BOOL)reset commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
        
    if (!_mfxTemporalScaler) {
        NSLog(@"Temporal scaler not initialized");
        return NO;
    }
    
    _mfxTemporalScaler.motionTexture = motionTexture;
    _mfxTemporalScaler.jitterOffsetX = jitterOffsetX;
    _mfxTemporalScaler.jitterOffsetY = jitterOffsetY;
    _mfxTemporalScaler.depthTexture = depthTexture;
    _mfxTemporalScaler.colorTexture = srcTexture;
    _mfxTemporalScaler.outputTexture = dstTexture;
    _mfxTemporalScaler.depthReversed = YES;
    _mfxTemporalScaler.reset = reset;
    
    [_mfxTemporalScaler encodeToCommandBuffer:commandBuffer];
    return YES;
}
+ (BOOL)isSupport:(id<MTLDevice>)device{
    if([MTLFXSpatialScalerDescriptor supportsDevice:device] and [MTLFXTemporalScalerDescriptor supportsDevice:device])
    {
        return YES;
    }
    return NO;
}
#else

+ (BOOL)buildSpatialScaler:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture processingMode:(int)processingMode device:(id<MTLDevice>)device {
    return NO;
}
+ (BOOL)buildTemporalScaler:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture depthTexture:(id<MTLTexture>)depthTexture motionTexture:(id<MTLTexture>)motionTexture device:(id<MTLDevice>)device {
    return NO;
}

+ (BOOL)callSpatialScaling:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    return NO;
}

+ (BOOL)callTemporalScaling:(id<MTLTexture>)srcTexture dstTexture:(id<MTLTexture>)dstTexture depthTexture:(id<MTLTexture>)depthTexture motionTexture:(id<MTLTexture>)motionTexture jitterOffsetX:(float)jitterOffsetX jitterOffsetY:(float)jitterOffsetY reset:(BOOL)reset commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    return NO;
}

+ (BOOL)isSupport:(id<MTLDevice>)device{
    return NO;
}



#endif
@end


