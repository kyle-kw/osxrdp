#import "ScreenRecorderImpl.h"

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#include <stdatomic.h>
#include <math.h>
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
    BOOL _forceFullAfterInvalidFrame;
    
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
        _forceFullAfterInvalidFrame = NO;
        atomic_store(&_callbacksEnabled, false);
    }
    
    return self;
}

int SetDirtyAreaInfoFromSampleBuffer(CMSampleBufferRef sampleBuffer, CGRect* rects);

static int CoalesceDirtyRectsToTiles(CFArrayRef dirtyArr, CGRect* rects) {
    const int tileSize = 64;
    CFIndex sourceCount = dirtyArr == NULL ? 0 : CFArrayGetCount(dirtyArr);
    if (sourceCount <= 0 || rects == NULL) return 0;

    CGRect bounds = CGRectNull;
    for (CFIndex i = 0; i < sourceCount; ++i) {
        CFTypeRef element = CFArrayGetValueAtIndex(dirtyArr, i);
        CGRect rect;
        if (element == NULL || CFGetTypeID(element) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)element, &rect)) {
            return OSXRDP_DIRTY_RECTS_FULL;
        }
        rect = CGRectStandardize(rect);
        if (!CGRectIsEmpty(rect)) bounds = CGRectIsNull(bounds) ? rect : CGRectUnion(bounds, rect);
    }
    if (CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) return 0;

    int minCol = MAX(0, (int)floor(CGRectGetMinX(bounds) / tileSize));
    int minRow = MAX(0, (int)floor(CGRectGetMinY(bounds) / tileSize));
    int maxCol = MAX(minCol + 1, (int)ceil(CGRectGetMaxX(bounds) / tileSize));
    int maxRow = MAX(minRow + 1, (int)ceil(CGRectGetMaxY(bounds) / tileSize));
    size_t columns = (size_t)(maxCol - minCol);
    size_t rows = (size_t)(maxRow - minRow);
    if (columns == 0 || rows == 0 || columns > SIZE_MAX / rows) {
        rects[0] = bounds;
        return 1;
    }
    uint8_t* tiles = (uint8_t*)calloc(columns * rows, 1);
    if (tiles == NULL) {
        rects[0] = bounds;
        return 1;
    }
    for (CFIndex i = 0; i < sourceCount; ++i) {
        CGRect rect;
        CGRectMakeWithDictionaryRepresentation(
            (CFDictionaryRef)CFArrayGetValueAtIndex(dirtyArr, i), &rect);
        rect = CGRectStandardize(rect);
        int left = MAX(minCol, (int)floor(CGRectGetMinX(rect) / tileSize));
        int top = MAX(minRow, (int)floor(CGRectGetMinY(rect) / tileSize));
        int right = MIN(maxCol, (int)ceil(CGRectGetMaxX(rect) / tileSize));
        int bottom = MIN(maxRow, (int)ceil(CGRectGetMaxY(rect) / tileSize));
        for (int row = top; row < bottom; ++row) {
            for (int col = left; col < right; ++col) {
                tiles[(size_t)(row - minRow) * columns + (size_t)(col - minCol)] = 1;
            }
        }
    }

    int outputCount = 0;
    for (int row = minRow; row < maxRow; ++row) {
        int col = minCol;
        while (col < maxCol) {
            while (col < maxCol && !tiles[(size_t)(row - minRow) * columns + (size_t)(col - minCol)]) ++col;
            if (col >= maxCol) break;
            int runStart = col;
            while (col < maxCol && tiles[(size_t)(row - minRow) * columns + (size_t)(col - minCol)]) ++col;
            CGFloat x = runStart * tileSize;
            CGFloat width = (col - runStart) * tileSize;
            bool merged = false;
            for (int existing = 0; existing < outputCount; ++existing) {
                if (rects[existing].origin.x == x && rects[existing].size.width == width &&
                    CGRectGetMaxY(rects[existing]) == row * tileSize) {
                    rects[existing].size.height += tileSize;
                    merged = true;
                    break;
                }
            }
            if (!merged) {
                if (outputCount >= MAX_DIRTY_COUNT) {
                    free(tiles);
                    rects[0] = bounds;
                    return 1;
                }
                rects[outputCount++] = CGRectMake(x, row * tileSize, width, tileSize);
            }
        }
    }
    free(tiles);
    return outputCount;
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
    
    if (recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED ||
        recordFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED ||
        recordFormat == OSXRDP_RECORDFORMAT_H264_ANNEXB) {
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
    if (dirtyAreaCnt == OSXRDP_DIRTY_RECTS_INVALID) {
        _forceFullAfterInvalidFrame = YES;
        return;
    }
    if (_forceFullAfterInvalidFrame) {
        dirtyAreaCnt = OSXRDP_DIRTY_RECTS_FULL;
        _forceFullAfterInvalidFrame = NO;
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
    if (sampleBuffer == NULL || rects == NULL) {
        return OSXRDP_DIRTY_RECTS_FULL;
    }
    CFArrayRef arr = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (arr == NULL || CFArrayGetCount(arr) == 0) {
        return OSXRDP_DIRTY_RECTS_FULL;
    }

    CFTypeRef attachment = CFArrayGetValueAtIndex(arr, 0);
    if (attachment == NULL || CFGetTypeID(attachment) != CFDictionaryGetTypeID()) {
        return OSXRDP_DIRTY_RECTS_FULL;
    }
    CFDictionaryRef att = (CFDictionaryRef)attachment;
    
    CFTypeRef statusValue = CFDictionaryGetValue(att, (__bridge CFStringRef)SCStreamFrameInfoStatus);
    if (statusValue == NULL || CFGetTypeID(statusValue) != CFNumberGetTypeID()) {
        return OSXRDP_DIRTY_RECTS_FULL;
    }

    NSNumber* status = (__bridge NSNumber*)statusValue;
    SCFrameStatus frameStatus = (SCFrameStatus)status.integerValue;
    if (frameStatus != SCFrameStatusComplete) {
        return OSXRDP_DIRTY_RECTS_INVALID;
    }

    CFTypeRef dirtyValue = CFDictionaryGetValue(att, (__bridge CFStringRef)SCStreamFrameInfoDirtyRects);
    if (dirtyValue == NULL || CFGetTypeID(dirtyValue) != CFArrayGetTypeID()) {
        return OSXRDP_DIRTY_RECTS_FULL;
    }
    CFArrayRef dirtyArr = (CFArrayRef)dirtyValue;
    
    int dirtyAreaCnt = (int)CFArrayGetCount(dirtyArr);
    if (dirtyAreaCnt > MAX_DIRTY_COUNT) {
        return CoalesceDirtyRectsToTiles(dirtyArr, rects);
    }
    
    for (int i = 0; i < dirtyAreaCnt; i++) {
        CFTypeRef element = CFArrayGetValueAtIndex(dirtyArr, i);
        if (element == NULL || CFGetTypeID(element) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)element, &(rects[i]))) {
            return OSXRDP_DIRTY_RECTS_FULL;
        }
    }
    
    return dirtyAreaCnt;
}

@end
