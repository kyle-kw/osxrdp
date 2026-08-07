#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class ScreenRecorderManager;

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

- (void)recordCommit:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos;
- (void)recordDrop:(int)displayIdx writePos:(unsigned int)writePos readPos:(unsigned int)readPos;
- (void)updateFromDisplayCount:(int)displayCount
                         width:(int)width
                        height:(int)height
                      framerate:(int)framerate
                   recordFormat:(int)recordFormat
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
void SessionMetricsGetSnapshot(int *displayCount, int *width, int *height,
                               int *fps, char *codecBuf, size_t codecBufLen, int *lag,
                               uint64_t *totalFrames, uint64_t *droppedFrames);

#ifdef __cplusplus
}
#endif
