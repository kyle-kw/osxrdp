#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface SessionMetrics : NSObject

@property (class, readonly, strong) SessionMetrics *shared;

@property (readonly) int activeDisplayCount;
@property (readonly) int currentWidth;
@property (readonly) int currentHeight;
@property (readonly) int currentFramerate;
@property (readonly) NSString *currentCodec;
@property (readonly) int frameLag;
@property (readonly) uint64_t totalFramesWritten;
@property (readonly) uint64_t droppedFrames;
@property (readonly) uint64_t copyFailures;
@property (readonly) uint64_t rfxFullRedrawRequests;
@property (readonly) uint64_t imeTimeouts;
- (void)recordCommit:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos;
- (void)recordDrop:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos;
- (void)recordCopyFailure;
- (void)recordRFXFullRedrawRequest;
- (void)recordIMETimeout;
- (void)recordEncodedBytes:(size_t)bytes keyframe:(BOOL)keyframe;
- (void)recordNoChangeSkip;
- (void)recordThrottledSkip;
- (void)updateFromDisplayCount:(int)displayCount
                         width:(int)width
                        height:(int)height
                      framerate:(int)framerate
                   recordFormat:(int)recordFormat
                         preset:(int)preset
                        writePos:(unsigned int)writePos
                         readPos:(unsigned int)readPos;

// Clear all counters/dimensions (e.g. on Stop) so diagnostics do not show stale session data.
- (void)reset;

@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
extern "C" {
#endif

// C-accessor bridge for C++ code (ConnectionDiagnostics.mm).
// codecBuf may be NULL; when non-NULL, the codec name is copied into it (NUL-terminated).
void SessionMetricsGetSnapshot(int * _Nullable displayCount,
                               int * _Nullable width,
                               int * _Nullable height,
                               int * _Nullable fps,
                               char * _Nullable codecBuf,
                               size_t codecBufLen,
                               int * _Nullable lag,
                               uint64_t * _Nullable totalFrames,
                               uint64_t * _Nullable droppedFrames,
                               uint64_t * _Nullable copyFailures,
                               uint64_t * _Nullable rfxFullRedrawRequests,
                               uint64_t * _Nullable imeTimeouts);
void SessionMetricsGetStreamingSnapshot(int * _Nullable preset,
                                        uint64_t * _Nullable encodedBytes,
                                        uint64_t * _Nullable recentBitsPerSecond,
                                        uint64_t * _Nullable noChangeSkips,
                                        uint64_t * _Nullable throttledSkips,
                                        uint64_t * _Nullable keyframes,
                                        uint64_t * _Nullable encoderFallbacks);

#ifdef __cplusplus
}
#endif
