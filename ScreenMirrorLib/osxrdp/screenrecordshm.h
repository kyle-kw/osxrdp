#ifndef screenrecordshm_h
#define screenrecordshm_h

#include <stdint.h>
#include <stdatomic.h>
#include <stddef.h>

#include <CoreFoundation/CoreFoundation.h>
#include "xshm.h"

#define FRAME_SLOTS             7
#define MAX_DIRTY_COUNT         128

// Bump both the layout version and the shared-memory name whenever the ABI of
// screenrecord_shm_t or screenrecord_frame_t changes. The versioned name keeps
// old processes from opening a mapping whose offsets they cannot understand.
#define OSXRDP_SCREENRECORD_SHM_MAGIC          0x4f535852U  // "OSXR"
#define OSXRDP_SCREENRECORD_SHM_LAYOUT_VERSION 2U
#define OSXRDP_SCREENRECORD_SHM_NAME           "/osxrdpshm_v2"

#define OSXRDP_FRAME_UPDATE_FULL  1
#define OSXRDP_FRAME_UPDATE_DIRTY 2

#define OSXRDP_FRAME_PAYLOAD_H264_ANNEXB 0x00000001U
#define OSXRDP_FRAME_PAYLOAD_KEYFRAME     0x00000002U
#define OSXRDP_FRAME_PAYLOAD_FORCE_FULL   0x00000004U

struct RECT {
    short x;
    short y;
    short width;
    short height;
};

#define MAX_CURSOR_IMG_BUFFER_SIZE (128 * 128)

typedef struct cursor_data {
    // Seqlock generation: odd while producer writes, even when stable.
    _Atomic unsigned int generation;
    int width;
    int height;
    int hotspotX;
    int hotspotY;
    int cursorImgDataSize;
    char cursorImgData[MAX_CURSOR_IMG_BUFFER_SIZE * 4]; //BGRA
    char cursorMaskData[MAX_CURSOR_IMG_BUFFER_SIZE]; //mask (dummy)
} cursor_data_t;

typedef struct screenrecord_frame {
    int updateKind;
    uint32_t payloadFlags;
    int dirtyCount;
    struct RECT dirtys[MAX_DIRTY_COUNT];
} screenrecord_frame_t;

typedef struct screenrecord_shm {
    uint32_t layoutMagic;
    uint32_t layoutVersion;
    uint32_t headerSize;
    uint32_t frameSize;
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

static inline int osxrdp_screenrecord_shm_is_compatible(
        const screenrecord_shm_t* shm, size_t mappedSize) {
    const size_t headerSize = offsetof(screenrecord_shm_t, screenrecord_datas);
    if (shm == NULL || mappedSize < headerSize ||
        shm->layoutMagic != OSXRDP_SCREENRECORD_SHM_MAGIC ||
        shm->layoutVersion != OSXRDP_SCREENRECORD_SHM_LAYOUT_VERSION ||
        shm->headerSize != headerSize ||
        shm->frameSize != sizeof(screenrecord_frame_t) ||
        shm->screenrecord_data_size == 0) {
        return 0;
    }
    return shm->screenrecord_data_size <=
        (mappedSize - headerSize) / FRAME_SLOTS;
}

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
