#import "SessionMetrics.h"
#import "osxrdp/packet.h"
#include <string.h>

// Single source of truth for recordFormat → display name (ObjC + C bridge).
static const char *CodecNameForRecordFormat(int fmt) {
    switch (fmt) {
        case OSXRDP_RECORDFORMAT_NV12_PACKED:
        case OSXRDP_RECORDFORMAT_NV12_ALIGNED:
            return "H.264";
        case OSXRDP_RECORDFORMAT_RFX:
            return "RFX";
        case OSXRDP_RECORDFORMAT_BGRA32:
            return "Bitmap";
        default:
            return "";
    }
}

@implementation SessionMetrics {
    dispatch_queue_t _queue;
    int _activeDisplayCount;
    int _currentWidth;
    int _currentHeight;
    int _currentFramerate;
    int _currentRecordFormat;
    unsigned int _writePos;
    unsigned int _readPos;
    uint64_t _totalFramesWritten;
    uint64_t _droppedFrames;
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
        _writePos = 0;
        _readPos = 0;
        _totalFramesWritten = 0;
        _droppedFrames = 0;
    }
    return self;
}

- (void)recordCommit:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos {
    (void)displayIdx;
    dispatch_async(_queue, ^{
        _totalFramesWritten++;
        _writePos = writePos;
        _readPos = readPos;
    });
}

- (void)recordDrop:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos {
    (void)displayIdx;
    dispatch_async(_queue, ^{
        _droppedFrames++;
        _writePos = writePos;
        _readPos = readPos;
    });
}

- (void)updateFromDisplayCount:(int)displayCount
                         width:(int)width
                        height:(int)height
                      framerate:(int)framerate
                   recordFormat:(int)recordFormat
                        writePos:(unsigned int)writePos
                         readPos:(unsigned int)readPos {
    dispatch_async(_queue, ^{
        _activeDisplayCount = displayCount;
        _currentWidth = width;
        _currentHeight = height;
        _currentFramerate = framerate;
        _currentRecordFormat = recordFormat;
        _writePos = writePos;
        _readPos = readPos;
    });
}

- (void)reset {
    dispatch_async(_queue, ^{
        _activeDisplayCount = 0;
        _currentWidth = 0;
        _currentHeight = 0;
        _currentFramerate = 0;
        _currentRecordFormat = -1;
        _writePos = 0;
        _readPos = 0;
        _totalFramesWritten = 0;
        _droppedFrames = 0;
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
    const char *name = CodecNameForRecordFormat(fmt);
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

- (void)copySnapshotToDisplayCount:(int *)displayCount
                             width:(int *)width
                            height:(int *)height
                         framerate:(int *)fps
                          codecBuf:(char *)codecBuf
                        codecBufLen:(size_t)codecBufLen
                               lag:(int *)lag
                       totalFrames:(uint64_t *)totalFrames
                     droppedFrames:(uint64_t *)droppedFrames {
    __block int bDisplay = 0, bWidth = 0, bHeight = 0, bFps = 0, bFmt = -1;
    __block unsigned int bWrite = 0, bRead = 0;
    __block uint64_t bTotal = 0, bDropped = 0;

    // Single queue sync so all fields come from one consistent instant.
    dispatch_sync(_queue, ^{
        bDisplay = _activeDisplayCount;
        bWidth = _currentWidth;
        bHeight = _currentHeight;
        bFps = _currentFramerate;
        bFmt = _currentRecordFormat;
        bWrite = _writePos;
        bRead = _readPos;
        bTotal = _totalFramesWritten;
        bDropped = _droppedFrames;
    });

    if (displayCount) *displayCount = bDisplay;
    if (width) *width = bWidth;
    if (height) *height = bHeight;
    if (fps) *fps = bFps;
    if (lag) *lag = (int)(bWrite - bRead);
    if (totalFrames) *totalFrames = bTotal;
    if (droppedFrames) *droppedFrames = bDropped;

    if (codecBuf != NULL && codecBufLen > 0) {
        const char *name = CodecNameForRecordFormat(bFmt);
        strncpy(codecBuf, name, codecBufLen - 1);
        codecBuf[codecBufLen - 1] = '\0';
    }
}

@end

#pragma mark - C bridge

void SessionMetricsGetSnapshot(int *displayCount, int *width, int *height,
                               int *fps, char *codecBuf, size_t codecBufLen, int *lag,
                               uint64_t *totalFrames, uint64_t *droppedFrames) {
    [SessionMetrics.shared copySnapshotToDisplayCount:displayCount
                                                width:width
                                               height:height
                                            framerate:fps
                                             codecBuf:codecBuf
                                           codecBufLen:codecBufLen
                                                  lag:lag
                                          totalFrames:totalFrames
                                        droppedFrames:droppedFrames];
}
