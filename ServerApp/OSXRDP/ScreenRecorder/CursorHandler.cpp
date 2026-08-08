//
//  CursorHandler.cpp
//  OSXRDP
//
//  Created by byungho on 2/9/26.
//

#include "CursorHandler.h"
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>

extern "C" {
    // private functions
    extern int CGSNewConnection(void* unused, int* newConnectionId);
    extern int CGSReleaseConnection(int connectionId);
    extern int CGSGetGlobalCursorDataSize(int connectionId, int* dataSize);
    extern int CGSGetGlobalCursorData(int connection, char *outData, int* ioDataSize, int* outRowBytes, CGRect* outRect, CGPoint* outHotspot, int* outDepth, int* outComponents, int* outBitsPerComponent);
    extern int CGSCurrentCursorSeed(void);
}

static inline int clamp_int(int v, int lo, int hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

CursorHandler::CursorHandler() :
    _connectionId(0),
    _cursorseed(0),
    _lastCheckTime(0)
{
    CGSNewConnection(NULL, &_connectionId);
    _tmpbuffer = (char*)malloc(128 * 128 * 4);
}

CursorHandler::~CursorHandler()
{
    CGSReleaseConnection(_connectionId);

    if (_tmpbuffer) {
        free(_tmpbuffer);
        _tmpbuffer = NULL;
    }
}

bool CursorHandler::HandleCursorInfo(cursor_data_t* cursor)
{
    // Update cursor if changed from previous
    int seed = CGSCurrentCursorSeed();
    if (seed == _cursorseed) {
        return false;
    }
    // Get cursor data size
    int datasize = 0;
    if (CGSGetGlobalCursorDataSize(_connectionId, &datasize) != 0) {
        return false;
    }

    // Check if size is valid
    if (datasize <= 0 || datasize > (128 * 128 * 4)) {
        return false;
    }

    int outRowBytes = 0;
    CGRect rect;
    CGPoint hotspot;
    int depth = 0;
    int comps = 0;
    int bpc = 0;

    // Get cursor data
    if (CGSGetGlobalCursorData(_connectionId,
                              _tmpbuffer,
                              &datasize,
                              &outRowBytes,
                              &rect,
                              &hotspot,
                              &depth,
                              &comps,
                              &bpc) != 0) {
        return false;
    }

    int srcW = (int)lround(rect.size.width);
    int srcH = (int)lround(rect.size.height);

    if (srcW <= 0 || srcH <= 0) {
        return false;
    }

    if (outRowBytes <= 0) {
        return false;
    }

    if (outRowBytes < srcW * 4) {
        return false;
    }

    if (datasize < outRowBytes * srcH) {
        return false;
    }

    // MS Windows apps on macOS are fine, but Windows mstsc seems to only accept square cursor shapes.
    // So find the nearest square size to draw on a square canvas.
    int dstSize = PickSquarePointerSize(srcW, srcH);
    if (dstSize > 96)
        dstSize = 96;

    if (dstSize * dstSize > MAX_CURSOR_IMG_BUFFER_SIZE) {
        return false;
    }

    int hotX = (int)lround(hotspot.x);
    int hotY = (int)lround(hotspot.y);

    hotX = clamp_int(hotX, 0, dstSize - 1);
    hotY = clamp_int(hotY, 0, dstSize - 1);

    unsigned int generation = atomic_load_explicit(&cursor->generation, memory_order_relaxed);
    if ((generation & 1U) != 0) generation++;
    atomic_store_explicit(&cursor->generation, generation + 1U, memory_order_relaxed);
    atomic_thread_fence(memory_order_seq_cst);

    cursor->width = dstSize;
    cursor->height = dstSize;
    cursor->hotspotX = hotX;
    cursor->hotspotY = hotY;

    // Draw (square)
    BuildSquarePointerBGRA(_tmpbuffer, outRowBytes, datasize, srcW, srcH, dstSize, cursor->cursorImgData);

    // Cursor image size
    cursor->cursorImgDataSize = cursor->width * cursor->height * 4;
        
    atomic_store_explicit(&cursor->generation, generation + 2U, memory_order_release);
    _cursorseed = seed;
    
    return true;
}

int CursorHandler::PickSquarePointerSize(int width, int height)
{
    int m = (width > height) ? width : height;

    if (m <= 32) return 32;
    if (m <= 48) return 48;
    if (m <= 64) return 64;
    return 96;
}

void CursorHandler::BuildSquarePointerBGRA(const char* src, int srcRowBytes, int srcSizeBytes, int srcWidth, int srcHeight, int dstSize, char* dstData)
{
    const int dstRowBytes = dstSize * 4;

    memset(dstData, 0x00, dstRowBytes * dstSize);

    int copyW = srcWidth;
    int copyH = srcHeight;

    if (copyW > dstSize) copyW = dstSize;
    if (copyH > dstSize) copyH = dstSize;

    if (srcRowBytes <= 0) return;
    if (srcSizeBytes < srcRowBytes * srcHeight) return;

    // RDP cursor requires vertical flip.
    for (int y = 0; y < copyH; ++y) {
        const uint8_t* srcRow = (const uint8_t*)src + y * srcRowBytes;
        uint8_t* dstRow = (uint8_t*)dstData + (dstSize - 1 - y) * dstRowBytes;
        memcpy(dstRow, srcRow, copyW * 4);
    }
}
