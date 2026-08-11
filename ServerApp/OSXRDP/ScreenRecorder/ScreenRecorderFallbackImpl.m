#import "ScreenRecorderFallbackImpl.h"
#include "osxrdp/packet.h"
#include <limits.h>
#include <stdatomic.h>

@implementation ScreenRecorderFallbackImpl {
    CGDisplayStreamRef _displayStream;
    NSDictionary* _recordConfig;
    dispatch_queue_t _recordQue;
    on_record_data _recordCb;
    on_record_cmd _recordCmdCb;
    void* _recordCbUserData;
    void* _recordCmdCbUserData;
    int _displayIdx;
    BOOL _intentionalStop;
    _Atomic bool _callbacksEnabled;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _displayStream = NULL;
        _recordConfig = NULL;
        _recordQue = nil;
        _recordCb = NULL;
        _recordCbUserData = NULL;
        _recordCmdCb = NULL;
        _recordCmdCbUserData = NULL;
        _intentionalStop = NO;
        atomic_store(&_callbacksEnabled, false);
    }
    return self;
}

- (void)initializeWithDisplayId:(int)displayId
            DisplayIndex:(int)displayIdx
            RecordWidth:(int)width
            RecordHeight:(int)height
            RecordFramerate:(int)framerate
            RecordFormat:(int)recordFormat
            RecordDataCallback:(on_record_data)recordCb
            RecordDataCallbackUserData:(void*)userData
            RecordCmdCallback:(on_record_cmd)recordCmdCb
            RecordCmdCallbackUserData:(void*)userData2 {
    
    CGRect destRect = CGRectMake(0, 0, width, height);
    CFDictionaryRef destRectDict = CGRectCreateDictionaryRepresentation(destRect);
    
    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    float frameTime = 1.0f / framerate;

    _recordConfig = @{
        (__bridge NSString*)kCGDisplayStreamShowCursor : @NO,
        (__bridge NSString*)kCGDisplayStreamQueueDepth : @3,
        (__bridge NSString*)kCGDisplayStreamMinimumFrameTime : @(frameTime),
        (__bridge NSString*)kCGDisplayStreamDestinationRect : (__bridge_transfer NSDictionary*)destRectDict,
        (__bridge NSString*)kCGDisplayStreamPreserveAspectRatio : @NO,      // Record ignoring aspect ratio (stretch)
        //(__bridge NSString*)kCGDisplayStreamColorSpace : (__bridge id)sRGB, // Without this setting, colors appear washed out
    };
    
    CGColorSpaceRelease(sRGB);

    CGDisplayStreamFrameAvailableHandler handler = ^(CGDisplayStreamFrameStatus status,
                                                     uint64_t displayTime,
                                                     IOSurfaceRef frameSurface,
                                                     CGDisplayStreamUpdateRef updateRef) {
        if (status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface != NULL) {
            // Recording callback
            [self processFrame:frameSurface displayTime:displayTime update:updateRef];
        }
        else if (status == kCGDisplayStreamFrameStatusStopped) {
            // Recording status callback (only terminate for unintentional stop)
            if (!self->_intentionalStop) {
                [self processStreamStopped];
            }
        }
    };
    
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    _recordQue = dispatch_queue_create("osxrdp.fallback_record", attr);
    
    int format = kCVPixelFormatType_32BGRA; // Standard bitmap
    if (recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED ||
        recordFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED ||
        recordFormat == OSXRDP_RECORDFORMAT_H264_ANNEXB) {
        format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange; // h264
    }
    else if (recordFormat == OSXRDP_RECORDFORMAT_RFX) {
        format = kCVPixelFormatType_32BGRA; // RFX (capture BGRA, convert to YUV444 upstream)
    }
    
    _displayStream = CGDisplayStreamCreateWithDispatchQueue(displayId, width, height, format, (__bridge CFDictionaryRef)_recordConfig, _recordQue, handler);
    _recordCb = recordCb;
    _recordCbUserData = userData;
    _recordCmdCb = recordCmdCb;
    _recordCmdCbUserData = userData2;
    _displayIdx = displayIdx;
    atomic_store_explicit(&_callbacksEnabled, true, memory_order_release);
}

- (BOOL)start {
    if (_recordQue == nil) {
         NSLog(@"[ScreenRecorderFallbackImpl::start] recordQue is NULL\n");
         return FALSE;
    }
    
    if (_displayStream == NULL) {
        NSLog(@"[ScreenRecorderFallbackImpl::start] displayStream is NULL\n");
        return FALSE;
    }
    
    NSLog(@"[ScreenRecorderFallbackImpl::start] before start record\n");
    
    CGError err = CGDisplayStreamStart(_displayStream);
    if (err != kCGErrorSuccess) {
        NSLog(@"[ScreenRecorderFallbackImpl::start] Failed to start stream: %d\n", err);
        atomic_store_explicit(&_callbacksEnabled, false, memory_order_release);
        CFRelease(_displayStream);
        _displayStream = NULL;
        return FALSE;
    }
    
    NSLog(@"[ScreenRecorderFallbackImpl::start] start record\n");
    return TRUE;
}

- (BOOL)stop {
    if (_displayStream == NULL) return YES;
    
    _intentionalStop = YES;
    atomic_store_explicit(&_callbacksEnabled, false, memory_order_release);
    CGError stopError = CGDisplayStreamStop(_displayStream);
    
    bool drained = true;
    if (_recordQue) {
        drained = false;
        dispatch_semaphore_t drainSema = dispatch_semaphore_create(0);
        dispatch_async(_recordQue, ^{ dispatch_semaphore_signal(drainSema); });
        drained = (dispatch_semaphore_wait(drainSema,
            dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC)) == 0);
    }
    
    CFRelease(_displayStream);
    _displayStream = NULL;
    
    NSLog(@"[ScreenRecorderFallbackImpl::stop] Stop Record\n");
    
    if (stopError != kCGErrorSuccess || !drained) {
        NSLog(@"[ScreenRecorderFallbackImpl::stop] teardown failed: stop=%d drained=%d",
              stopError, drained);
        return NO;
    }
    return YES;
}

- (void)processFrame:(IOSurfaceRef)ioSurface displayTime:(uint64_t)displayTime update:(CGDisplayStreamUpdateRef)updateRef {
    if (_recordCb == NULL || !atomic_load_explicit(&_callbacksEnabled, memory_order_acquire)) return;

    CVPixelBufferRef pixelBuffer = NULL;
    
    CVReturn cvErr = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, ioSurface, NULL, &pixelBuffer);
    if (cvErr != kCVReturnSuccess) {
        return;
    }
    
    // Get dirty rects
    size_t dirtyRectsCnt = 0;
    const CGRect* dirtyRects = updateRef == NULL ? NULL
        : CGDisplayStreamUpdateGetRects(updateRef, kCGDisplayStreamUpdateDirtyRects,
                                        &dirtyRectsCnt);
    int callbackDirtyCount = (updateRef == NULL ||
                              dirtyRectsCnt > INT_MAX ||
                              (dirtyRectsCnt > 0 && dirtyRects == NULL))
        ? OSXRDP_DIRTY_RECTS_FULL : (int)dirtyRectsCnt;
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Deliver recording callback
    if (atomic_load_explicit(&_callbacksEnabled, memory_order_acquire)) {
        _recordCb(pixelBuffer, dirtyRects, callbackDirtyCount,
                  _recordCbUserData, _displayIdx);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    CVPixelBufferRelease(pixelBuffer);
}

- (void)processStreamStopped {
    if (atomic_load_explicit(&_callbacksEnabled, memory_order_acquire) && _recordCmdCb != NULL) {
        _recordCmdCb(1, _recordCmdCbUserData);
    }
}

@end
