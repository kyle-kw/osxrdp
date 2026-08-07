#ifndef screenrecordshm_h
#define screenrecordshm_h

#include <stdint.h>
#include <stdatomic.h>

#include <CoreFoundation/CoreFoundation.h>
#include "xshm.h"

#define FRAME_SLOTS             7
#define MAX_DIRTY_COUNT         128

struct RECT {
    short x;
    short y;
    short width;
    short height;
};

#define MAX_CURSOR_IMG_BUFFER_SIZE (128 * 128)

typedef struct cursor_data {
    _Atomic int updated;
    int width;
    int height;
    int hotspotX;
    int hotspotY;
    int cursorImgDataSize;
    char cursorImgData[MAX_CURSOR_IMG_BUFFER_SIZE * 4]; //BGRA
    char cursorMaskData[MAX_CURSOR_IMG_BUFFER_SIZE]; //mask (dummy)
} cursor_data_t;

typedef struct screenrecord_frame {
    int dirtyCount;  // <--- if this is 0, full redraw
    struct RECT dirtys[MAX_DIRTY_COUNT];
} screenrecord_frame_t;

typedef struct screenrecord_shm {
    _Atomic unsigned int write_pos;
    _Atomic unsigned int read_pos;
    int width;
    int height;
    int fps;
    // Signal to ServerApp to fill a full frame when osxup needs a full redraw. (Used only with RFX which supports partial frames)
    _Atomic int consumer_request_full;
    screenrecord_frame_t frames[FRAME_SLOTS];
    size_t screenrecord_data_size;
    char screenrecord_datas[1];
} screenrecord_shm_t;

// ---------------------------------------------------------------------------
// RFX dirty-only SHM slot layout (recordFormat == OSXRDP_RECORDFORMAT_RFX)
// ---------------------------------------------------------------------------
//   offset 0             : size_t imgSize
//                            = sizeof(int)                              // tileCount
//                            + sizeof(int) * tileCount                  // indices
//                            + 16384 * tileCount                        // tile payload
//   offset sizeof(size_t): int tileCount                                // number of tiles included in this slot
//   followed by          : int indices[tileCount]                       // row-major global tile indices
//   followed by          : uint8_t tileData[tileCount * 16384]          // YUV444 planar (Y, U, V, A)
//
// If tileCount equals the total tile count of the frame (tileCols * tileRows)
// it is a full redraw frame. Otherwise it is a dirty-only frame.
// ---------------------------------------------------------------------------
#define OSXRDP_RFX_TILE_BYTES (16384)  // 64 x 64 x (Y + U + V + A)


#endif /* screenrecordshm_h */
