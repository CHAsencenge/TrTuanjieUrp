//
//  MTLUtils.h
//  MetalUpscaling
//
//  Created by jadiek on 2025/6/19.
//

#ifndef MTLUtils_h
#define MTLUtils_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
// #import <MetalFX/MetalFX.h>

@interface MTLUtils : NSObject

//+ (void)setCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
//+ (void)setDevice:(id<MTLDevice>)device;

+ (BOOL)buildTemporalScaler:(id<MTLTexture>)srcTexture
                dstTexture:(id<MTLTexture>)dstTexture
              depthTexture:(id<MTLTexture>)depthTexture
             motionTexture:(id<MTLTexture>)motionTexture
            device:(id<MTLDevice>)device;

+ (BOOL)buildSpatialScaler:(id<MTLTexture>)srcTexture
               dstTexture:(id<MTLTexture>)dstTexture
          processingMode:(int)processingMode
                    device:(id<MTLDevice>)device;

+ (BOOL)callTemporalScaling:(id<MTLTexture>)srcTexture
                dstTexture:(id<MTLTexture>)dstTexture
              depthTexture:(id<MTLTexture>)depthTexture
             motionTexture:(id<MTLTexture>)motionTexture
            jitterOffsetX:(float)jitterOffsetX
            jitterOffsetY:(float)jitterOffsetY
                    reset:(BOOL)reset
            commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

+ (BOOL)callSpatialScaling:(id<MTLTexture>)srcTexture
               dstTexture:(id<MTLTexture>)dstTexture
             commandBuffer:(id<MTLCommandBuffer>)commandBuffer;
+ (BOOL)isSupport:(id<MTLDevice>)device;

@end

#endif /* MTLUtils_h */
