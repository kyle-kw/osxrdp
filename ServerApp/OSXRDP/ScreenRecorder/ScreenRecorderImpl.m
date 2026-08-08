#import "ScreenRecorderImpl.h"

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#include <stdatomic.h>
#include "osxrdp/packet.h"
#include "osxrdp/screenrecordshm.h"

@implementation ScreenRecorderImpl {
    SCContentFilter* _recordFilter;
    SCStreamConfiguration* _recordConfig;
    dispatch_queue_t _recordQue;
    SCStream* _recordStream;
    on_record_data _recordCb;
    on_record_cmd _recordCmdCb;
    void* _recordCbUserData;
    void* _recordCmdCbUserData;
    int _displayIdx;
    _Atomic bool _callbacksEnabled;
    
    CGRect _dirtyRectBuffer[MAX_DIRTY_COUNT];
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _recordFilter = nil;
        _recordConfig = nil;
        _recordQue = nil;
        _recordStream = nil;
        _recordCb = NULL;
        _recordCbUserData = NULL;
        atomic_store(&_callbacksEnabled, false);
    }
    
    return self;
}

int SetDirtyAreaInfoFromSampleBuffer(CMSampleBufferRef sampleBuffer, CGRect* rects);

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
    
    SCDisplay* display = [self getDisplayFromDisplayId: displayId];
    if (display == nil) return;
    
    _recordFilter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
    if (_recordFilter == nil) return;
    
    // Recording configuration (resolution, frame rate, etc.)
    _recordConfig = [[SCStreamConfiguration alloc] init];
    _recordConfig.width = width;
    _recordConfig.height = height;
    _recordConfig.queueDepth = framerate >= 60 ? 4 : 3;
    
    //_recordConfig.colorSpaceName = kCGColorSpaceSRGB;
    
    if (recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED || recordFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED) {
        // When using H.264
        _recordConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    }
    else if (recordFormat == OSXRDP_RECORDFORMAT_RFX) {
        // When using RFX (capture BGRA for ScreenCaptureKit compatibility, convert to YUV444 upstream)
        _recordConfig.pixelFormat = kCVPixelFormatType_32BGRA;
    }
    else {
        // When using bitmap
        _recordConfig.pixelFormat = kCVPixelFormatType_32BGRA;
    }
    
    _recordConfig.showsCursor = NO;
    // Older OS uses ScreenRecorderFallback.
    if (@available(macOS 14.0,*)) {
        _recordConfig.preservesAspectRatio = NO;
    }
    
    _recordConfig.minimumFrameInterval = CMTimeMake(1, framerate);
    
    // Recording queue setup
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    _recordQue = dispatch_queue_create("osxrdp.record", attr);
    
    // Recording data callback (to deliver encoded data)
    _recordCb = recordCb;
    _recordCbUserData = userData;
    
    // Recording event callback (to receive sudden stop events)
    _recordCmdCb = recordCmdCb;
    _recordCmdCbUserData = userData2;
    
    _displayIdx = displayIdx;
    atomic_store_explicit(&_callbacksEnabled, true, memory_order_release);
}

- (BOOL)start {
    if (_recordFilter == nil) {
        NSLog(@"[ScreenRecorderImpl::start] recordFilter is NULL\n");
        
        return NO;
    }
    
    if (_recordConfig == nil) {
        NSLog(@"[ScreenRecorderImpl::start] recordConfig is NULL\n");
        
        return NO;
    }
    
    if (_recordQue == nil) {
        NSLog(@"[ScreenRecorderImpl::start] recordQue is NULL\n");
        
        return NO;
    }
    
    _recordStream = [[SCStream alloc] initWithFilter:_recordFilter configuration:_recordConfig delegate:self];
    
    NSError* err = nil;
    [_recordStream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:_recordQue error:&err];
    if (err != nil) {
        NSLog(@"[ScreenRecorderImpl::start] addStreamOutput failed. %ld\n", err.code);
        atomic_store_explicit(&_callbacksEnabled, false, memory_order_release);
        return NO;
    }
    
    NSLog(@"[ScreenRecorderImpl::start] before start record\n");
    __block NSError* startError = nil;
    dispatch_semaphore_t startSema = dispatch_semaphore_create(0);
    [_recordStream startCaptureWithCompletionHandler:^(NSError* _Nullable error) {
        startError = error;
        dispatch_semaphore_signal(startSema);
    }];
    long startWait = dispatch_semaphore_wait(startSema,
        dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    if (startWait != 0 || startError != nil) {
        NSLog(@"[ScreenRecorderImpl::start] start failed or timed out: %@",
              startError ?: @"timeout");
        atomic_store_explicit(&_callbacksEnabled, false, memory_order_release);
        // Keep the stream attached for the manager's common bounded Stop path;
        // it drains the callback queue before releasing the callback context.
        return NO;
    }
    NSLog(@"[ScreenRecorderImpl::start] start record\n");

    return YES;
}

- (BOOL)stop {
    if (_recordStream == nil) return YES;
    atomic_store_explicit(&_callbacksEnabled, false, memory_order_release);
    
    // Wait for recording to fully stop after stop request
    __block NSError* stopError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [_recordStream stopCaptureWithCompletionHandler:^(NSError* _Nullable err) {
        stopError = err;
        
        dispatch_semaphore_signal(sema);
    }];
    long stopWait = dispatch_semaphore_wait(sema,
        dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    if (stopWait != 0) {
        NSLog(@"[ScreenRecorderImpl::stop] stop timed out; detaching output");
    }
    else if (stopError != nil) {
        NSLog(@"[ScreenRecorderImpl::stop] stop returned error: %ld", stopError.code);
    }

    NSError* removeError = nil;
    [_recordStream removeStreamOutput:self type:SCStreamOutputTypeScreen error:&removeError];

    __block bool drained = true;
    if (_recordQue) {
        drained = false;
        dispatch_semaphore_t drainSema = dispatch_semaphore_create(0);
        dispatch_async(_recordQue, ^{
            dispatch_semaphore_signal(drainSema);
        });
        drained = (dispatch_semaphore_wait(drainSema,
            dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC)) == 0);
    }

    _recordStream = nil;
    _recordFilter = nil;
    _recordConfig = nil;
    if (stopWait != 0 || stopError != nil || removeError != nil || drained == false) {
        NSLog(@"[ScreenRecorderImpl::stop] teardown failed: stopWait=%ld stop=%@ remove=%@ drained=%d",
              stopWait, stopError, removeError, drained);
        return NO;
    }

    NSLog(@"[ScreenRecorderImpl::stop] Stop Record\n");
    return YES;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (!atomic_load_explicit(&_callbacksEnabled, memory_order_acquire)) return;
    
    // Extract dirty area info
    int dirtyAreaCnt = SetDirtyAreaInfoFromSampleBuffer(sampleBuffer, _dirtyRectBuffer);
    if (dirtyAreaCnt < 0) {
        return;
    }
    
    // Extract ImageBuffer (same as CVPixelBufferRef)
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Call callback (send screen data to osxup)
    if (atomic_load_explicit(&_callbacksEnabled, memory_order_acquire) && _recordCb != NULL) {
        _recordCb(pixelBuffer, _dirtyRectBuffer, dirtyAreaCnt, _recordCbUserData, _displayIdx);
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    // Request recording stop
    if (atomic_load_explicit(&_callbacksEnabled, memory_order_acquire) && _recordCmdCb != NULL) {
        _recordCmdCb(1, _recordCmdCbUserData);
    }
}

// Look up ScreenCaptureKit display by display ID
- (SCDisplay*)getDisplayFromDisplayId:(int)displayId {
    __block SCDisplay* found = nil;
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content, NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"[ScreenRecorderImpl] display lookup failed: %@", error);
        }
        for (SCDisplay* item in content.displays) {
            if (item.displayID == displayId) {
                found = item;
                break;
            }
        }
        dispatch_semaphore_signal(sema);
    }];

    long waitResult = dispatch_semaphore_wait(sema,
        dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    if (waitResult != 0) {
        NSLog(@"[ScreenRecorderImpl] display lookup timed out for id %d", displayId);
        return nil;
    }

    return found;
}

int SetDirtyAreaInfoFromSampleBuffer(CMSampleBufferRef sampleBuffer, CGRect* rects) {
    CFArrayRef arr = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (arr == NULL || CFArrayGetCount(arr) == 0) {
        return -1;
    }

    CFDictionaryRef att = (CFDictionaryRef)CFArrayGetValueAtIndex(arr, 0);
    if (att == NULL) {
        return -1;
    }
    
    NSNumber* status = (__bridge NSNumber*)CFDictionaryGetValue(att, (__bridge CFStringRef)SCStreamFrameInfoStatus);
    if (status == nil) {
        return -1;
    }

    SCFrameStatus frameStatus = (SCFrameStatus)status.integerValue;
    if (frameStatus != SCFrameStatusComplete) {
        return -1;
    }

    CFArrayRef dirtyArr = (CFArrayRef)CFDictionaryGetValue(att, (__bridge CFStringRef)SCStreamFrameInfoDirtyRects);
    if (dirtyArr == NULL) {
        return 0;
    }
    
    int dirtyAreaCnt = (int)CFArrayGetCount(dirtyArr);
    if (dirtyAreaCnt > MAX_DIRTY_COUNT) return 0;
    
    for (int i = 0; i < dirtyAreaCnt; i++) {
        CFTypeRef element = CFArrayGetValueAtIndex(dirtyArr, i);
        if (element == NULL || CFGetTypeID(element) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)element, &(rects[i]))) {
            return 0;
        }
    }
    
    return dirtyAreaCnt;
}

@end
