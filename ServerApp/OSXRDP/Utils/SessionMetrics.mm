#import "SessionMetrics.h"
#import "osxrdp/packet.h"
#import "osxrdp/stream_policy.h"
#include <string.h>
#include <time.h>

// Single source of truth for recordFormat → display name (ObjC + C bridge).
static const char *CodecNameForRecordFormat(int fmt, int preset) {
    switch (fmt) {
        case OSXRDP_RECORDFORMAT_NV12_PACKED:
        case OSXRDP_RECORDFORMAT_NV12_ALIGNED:
            return preset == OSXRDP_STREAM_QUALITY_HIGH ? "OpenH264" : "OpenH264 fallback";
        case OSXRDP_RECORDFORMAT_H264_ANNEXB:
            return "VideoToolbox H.264";
        case OSXRDP_RECORDFORMAT_RFX:
            return "RFX";
        case OSXRDP_RECORDFORMAT_BGRA32:
            return "Bitmap";
        default:
            return "";
    }
}

int SessionMetricsBitrateBucketForSecond(time_t second) {
    if (second < 0) return -1;
    return (int)((uint64_t)second % 5);
}

@interface SessionMetrics ()
- (void)copyStreamingPreset:(int *)preset encodedBytes:(uint64_t *)encodedBytes
        recentBitsPerSecond:(uint64_t *)recentBitsPerSecond
              noChangeSkips:(uint64_t *)noChangeSkips
             throttledSkips:(uint64_t *)throttledSkips
                 keyframes:(uint64_t *)keyframes
          encoderFallbacks:(uint64_t *)encoderFallbacks;
@end

@implementation SessionMetrics {
    dispatch_queue_t _queue;
    int _activeDisplayCount;
    int _currentWidth;
    int _currentHeight;
    int _currentFramerate;
    int _currentRecordFormat;
    int _currentPreset;
    unsigned int _writePos;
    unsigned int _readPos;
    uint64_t _totalFramesWritten;
    uint64_t _droppedFrames;
    uint64_t _copyFailures;
    uint64_t _rfxFullRedrawRequests;
    uint64_t _imeTimeouts;
    uint64_t _encodedScreenBytes;
    uint64_t _noChangeSkips;
    uint64_t _throttledSkips;
    uint64_t _keyframes;
    uint64_t _encoderFallbacks;
    uint64_t _bitrateBytes[5];
    time_t _bitrateSeconds[5];
}

+ (instancetype)shared {
    static SessionMetrics *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[SessionMetrics alloc] init];
    });
    return sInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.osxrdp.sessionmetrics", DISPATCH_QUEUE_SERIAL);
        _activeDisplayCount = 0;
        _currentWidth = 0;
        _currentHeight = 0;
        _currentFramerate = 0;
        _currentRecordFormat = -1;
        _currentPreset = OSXRDP_STREAM_QUALITY_DEFAULT;
        _writePos = 0;
        _readPos = 0;
        _totalFramesWritten = 0;
        _droppedFrames = 0;
        _copyFailures = 0;
        _rfxFullRedrawRequests = 0;
        _imeTimeouts = 0;
        memset(_bitrateBytes, 0, sizeof(_bitrateBytes));
        memset(_bitrateSeconds, 0, sizeof(_bitrateSeconds));
    }
    return self;
}

- (void)recordCopyFailure {
    dispatch_async(_queue, ^{ self->_copyFailures++; });
}

- (void)recordRFXFullRedrawRequest {
    dispatch_async(_queue, ^{ self->_rfxFullRedrawRequests++; });
}

- (void)recordIMETimeout {
    dispatch_async(_queue, ^{ self->_imeTimeouts++; });
}

- (void)recordEncodedBytes:(size_t)bytes keyframe:(BOOL)keyframe {
    dispatch_async(_queue, ^{
        self->_encodedScreenBytes += bytes;
        if (keyframe) self->_keyframes++;
        time_t second = time(NULL);
        int bucket = SessionMetricsBitrateBucketForSecond(second);
        if (bucket < 0) return;
        if (self->_bitrateSeconds[bucket] != second) {
            self->_bitrateSeconds[bucket] = second;
            self->_bitrateBytes[bucket] = 0;
        }
        self->_bitrateBytes[bucket] += bytes;
    });
}

- (void)recordNoChangeSkip { dispatch_async(_queue, ^{ self->_noChangeSkips++; }); }
- (void)recordThrottledSkip { dispatch_async(_queue, ^{ self->_throttledSkips++; }); }

- (void)recordCommit:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos {
    (void)displayIdx;
    dispatch_async(_queue, ^{
        self->_totalFramesWritten++;
        self->_writePos = writePos;
        self->_readPos = readPos;
    });
}

- (void)recordDrop:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos {
    (void)displayIdx;
    dispatch_async(_queue, ^{
        self->_droppedFrames++;
        self->_writePos = writePos;
        self->_readPos = readPos;
    });
}

- (void)updateFromDisplayCount:(int)displayCount
                         width:(int)width
                        height:(int)height
                      framerate:(int)framerate
                   recordFormat:(int)recordFormat
                         preset:(int)preset
                        writePos:(unsigned int)writePos
                         readPos:(unsigned int)readPos {
    dispatch_async(_queue, ^{
        self->_activeDisplayCount = displayCount;
        self->_currentWidth = width;
        self->_currentHeight = height;
        self->_currentFramerate = framerate;
        self->_currentRecordFormat = recordFormat;
        self->_currentPreset = osxrdp_stream_quality_is_valid(preset)
            ? preset : OSXRDP_STREAM_QUALITY_DEFAULT;
        if (self->_currentPreset != OSXRDP_STREAM_QUALITY_HIGH &&
            recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED) {
            self->_encoderFallbacks++;
        }
        self->_writePos = writePos;
        self->_readPos = readPos;
    });
}

- (void)reset {
    dispatch_async(_queue, ^{
        self->_activeDisplayCount = 0;
        self->_currentWidth = 0;
        self->_currentHeight = 0;
        self->_currentFramerate = 0;
        self->_currentRecordFormat = -1;
        self->_currentPreset = OSXRDP_STREAM_QUALITY_DEFAULT;
        self->_writePos = 0;
        self->_readPos = 0;
        self->_totalFramesWritten = 0;
        self->_droppedFrames = 0;
        self->_copyFailures = 0;
        self->_rfxFullRedrawRequests = 0;
        self->_imeTimeouts = 0;
        self->_encodedScreenBytes = 0;
        self->_noChangeSkips = 0;
        self->_throttledSkips = 0;
        self->_keyframes = 0;
        self->_encoderFallbacks = 0;
        memset(self->_bitrateBytes, 0, sizeof(self->_bitrateBytes));
        memset(self->_bitrateSeconds, 0, sizeof(self->_bitrateSeconds));
    });
}

#pragma mark - Read-only properties

- (int)activeDisplayCount {
    __block int val = 0;
    dispatch_sync(_queue, ^{ val = _activeDisplayCount; });
    return val;
}

- (int)currentWidth {
    __block int val = 0;
    dispatch_sync(_queue, ^{ val = _currentWidth; });
    return val;
}

- (int)currentHeight {
    __block int val = 0;
    dispatch_sync(_queue, ^{ val = _currentHeight; });
    return val;
}

- (int)currentFramerate {
    __block int val = 0;
    dispatch_sync(_queue, ^{ val = _currentFramerate; });
    return val;
}

- (NSString *)currentCodec {
    __block int fmt = 0;
    dispatch_sync(_queue, ^{ fmt = _currentRecordFormat; });
    __block int preset = 0;
    dispatch_sync(_queue, ^{ preset = _currentPreset; });
    const char *name = CodecNameForRecordFormat(fmt, preset);
    return name[0] != '\0' ? [NSString stringWithUTF8String:name] : @"";
}

- (int)frameLag {
    __block unsigned int w = 0, r = 0;
    dispatch_sync(_queue, ^{ w = _writePos; r = _readPos; });
    return (int)(w - r);
}

- (uint64_t)totalFramesWritten {
    __block uint64_t val = 0;
    dispatch_sync(_queue, ^{ val = _totalFramesWritten; });
    return val;
}

- (uint64_t)droppedFrames {
    __block uint64_t val = 0;
    dispatch_sync(_queue, ^{ val = _droppedFrames; });
    return val;
}

- (uint64_t)copyFailures {
    __block uint64_t val = 0;
    dispatch_sync(_queue, ^{ val = _copyFailures; });
    return val;
}

- (uint64_t)rfxFullRedrawRequests {
    __block uint64_t val = 0;
    dispatch_sync(_queue, ^{ val = _rfxFullRedrawRequests; });
    return val;
}

- (uint64_t)imeTimeouts {
    __block uint64_t val = 0;
    dispatch_sync(_queue, ^{ val = _imeTimeouts; });
    return val;
}

- (void)copySnapshotToDisplayCount:(int *)displayCount
                             width:(int *)width
                            height:(int *)height
                         framerate:(int *)fps
                          codecBuf:(char *)codecBuf
                        codecBufLen:(size_t)codecBufLen
                               lag:(int *)lag
                       totalFrames:(uint64_t *)totalFrames
                     droppedFrames:(uint64_t *)droppedFrames
                      copyFailures:(uint64_t *)copyFailures
             rfxFullRedrawRequests:(uint64_t *)rfxFullRedrawRequests
                       imeTimeouts:(uint64_t *)imeTimeouts {
    __block int bDisplay = 0, bWidth = 0, bHeight = 0, bFps = 0, bFmt = -1, bPreset = 0;
    __block unsigned int bWrite = 0, bRead = 0;
    __block uint64_t bTotal = 0, bDropped = 0;
    __block uint64_t bCopyFailures = 0, bRFXRequests = 0, bIMETimeouts = 0;

    // Single queue sync so all fields come from one consistent instant.
    dispatch_sync(_queue, ^{
        bDisplay = _activeDisplayCount;
        bWidth = _currentWidth;
        bHeight = _currentHeight;
        bFps = _currentFramerate;
        bFmt = _currentRecordFormat;
        bPreset = _currentPreset;
        bWrite = _writePos;
        bRead = _readPos;
        bTotal = _totalFramesWritten;
        bDropped = _droppedFrames;
        bCopyFailures = _copyFailures;
        bRFXRequests = _rfxFullRedrawRequests;
        bIMETimeouts = _imeTimeouts;
    });

    if (displayCount) *displayCount = bDisplay;
    if (width) *width = bWidth;
    if (height) *height = bHeight;
    if (fps) *fps = bFps;
    if (lag) *lag = (int)(bWrite - bRead);
    if (totalFrames) *totalFrames = bTotal;
    if (droppedFrames) *droppedFrames = bDropped;
    if (copyFailures) *copyFailures = bCopyFailures;
    if (rfxFullRedrawRequests) *rfxFullRedrawRequests = bRFXRequests;
    if (imeTimeouts) *imeTimeouts = bIMETimeouts;

    if (codecBuf != NULL && codecBufLen > 0) {
        const char *name = CodecNameForRecordFormat(bFmt, bPreset);
        strncpy(codecBuf, name, codecBufLen - 1);
        codecBuf[codecBufLen - 1] = '\0';
    }
}

- (void)copyStreamingPreset:(int *)preset encodedBytes:(uint64_t *)encodedBytes
        recentBitsPerSecond:(uint64_t *)recentBitsPerSecond
              noChangeSkips:(uint64_t *)noChangeSkips
           throttledSkips:(uint64_t *)throttledSkips
                 keyframes:(uint64_t *)keyframes
          encoderFallbacks:(uint64_t *)encoderFallbacks {
    __block int bPreset = OSXRDP_STREAM_QUALITY_DEFAULT;
    __block uint64_t bBytes = 0, bNoChange = 0, bThrottled = 0, bKeyframes = 0, bFallbacks = 0;
    __block uint64_t bRecentBytes = 0;
    dispatch_sync(_queue, ^{
        bPreset = _currentPreset;
        bBytes = _encodedScreenBytes;
        bNoChange = _noChangeSkips;
        bThrottled = _throttledSkips;
        bKeyframes = _keyframes;
        bFallbacks = _encoderFallbacks;
        time_t now = time(NULL);
        for (int i = 0; i < 5; ++i) {
            if (now >= _bitrateSeconds[i] && now - _bitrateSeconds[i] < 5) {
                bRecentBytes += _bitrateBytes[i];
            }
        }
    });
    if (preset) *preset = bPreset;
    if (encodedBytes) *encodedBytes = bBytes;
    if (recentBitsPerSecond) *recentBitsPerSecond = (bRecentBytes * 8) / 5;
    if (noChangeSkips) *noChangeSkips = bNoChange;
    if (throttledSkips) *throttledSkips = bThrottled;
    if (keyframes) *keyframes = bKeyframes;
    if (encoderFallbacks) *encoderFallbacks = bFallbacks;
}

@end

#pragma mark - C bridge

void SessionMetricsGetSnapshot(int *displayCount, int *width, int *height,
                               int *fps, char *codecBuf, size_t codecBufLen, int *lag,
                               uint64_t *totalFrames, uint64_t *droppedFrames,
                               uint64_t *copyFailures, uint64_t *rfxFullRedrawRequests,
                               uint64_t *imeTimeouts) {
    [SessionMetrics.shared copySnapshotToDisplayCount:displayCount
                                                width:width
                                               height:height
                                            framerate:fps
                                             codecBuf:codecBuf
                                           codecBufLen:codecBufLen
                                                  lag:lag
                                          totalFrames:totalFrames
                                        droppedFrames:droppedFrames
                                         copyFailures:copyFailures
                                rfxFullRedrawRequests:rfxFullRedrawRequests
                                          imeTimeouts:imeTimeouts];
}

void SessionMetricsGetStreamingSnapshot(int *preset, uint64_t *encodedBytes,
                                        uint64_t *recentBitsPerSecond,
                                        uint64_t *noChangeSkips,
                                        uint64_t *throttledSkips,
                                        uint64_t *keyframes,
                                        uint64_t *encoderFallbacks) {
    [SessionMetrics.shared copyStreamingPreset:preset
                                  encodedBytes:encodedBytes
                           recentBitsPerSecond:recentBitsPerSecond
                                 noChangeSkips:noChangeSkips
                                throttledSkips:throttledSkips
                                      keyframes:keyframes
                               encoderFallbacks:encoderFallbacks];
}
