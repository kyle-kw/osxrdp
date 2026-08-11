#ifndef osxrdp_dirty_region_h
#define osxrdp_dirty_region_h

#include "screenrecordshm.h"

#ifdef __cplusplus
extern "C" {
#endif

#define OSXRDP_DIRTY_MERGE_EMPTY 0
#define OSXRDP_DIRTY_MERGE_DIRTY 1
#define OSXRDP_DIRTY_MERGE_FULL  2

// Appends rectangles and, when the 128-rectangle limit is exceeded, rasterizes
// them to 64x64 tiles, merging horizontal runs and equal vertical spans.
int osxrdp_dirty_region_merge(struct RECT* rects, int* rectCount,
                              const struct RECT* additions, int additionCount,
                              int width, int height);

#ifdef __cplusplus
}
#endif

#endif /* osxrdp_dirty_region_h */
