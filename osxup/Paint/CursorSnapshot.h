#ifndef CursorSnapshot_h
#define CursorSnapshot_h

#include "osxrdp/screenrecordshm.h"
#include <string.h>

struct CursorSnapshot {
    unsigned int generation;
    int width;
    int height;
    int hotspotX;
    int hotspotY;
    int imageSize;
    char image[MAX_CURSOR_IMG_BUFFER_SIZE * 4];
    char mask[MAX_CURSOR_IMG_BUFFER_SIZE];
};

inline bool TryCopyCursorSnapshot(const cursor_data_t* cursor,
                                  unsigned int lastGeneration,
                                  CursorSnapshot* snapshot) {
    if (cursor == NULL || snapshot == NULL) return false;

    unsigned int generationBefore =
        atomic_load_explicit(&cursor->generation, memory_order_acquire);
    if (generationBefore == 0 || (generationBefore & 1U) != 0 ||
        generationBefore == lastGeneration) return false;

    int width = cursor->width;
    int height = cursor->height;
    int imageSize = cursor->cursorImgDataSize;
    if (width <= 0 || height <= 0 || width > 128 || height > 128 ||
        width > MAX_CURSOR_IMG_BUFFER_SIZE / height ||
        imageSize != width * height * 4) return false;

    snapshot->width = width;
    snapshot->height = height;
    snapshot->hotspotX = cursor->hotspotX;
    snapshot->hotspotY = cursor->hotspotY;
    snapshot->imageSize = imageSize;
    memcpy(snapshot->image, cursor->cursorImgData, (size_t)imageSize);
    memcpy(snapshot->mask, cursor->cursorMaskData, MAX_CURSOR_IMG_BUFFER_SIZE);

    atomic_thread_fence(memory_order_seq_cst);
    unsigned int generationAfter =
        atomic_load_explicit(&cursor->generation, memory_order_acquire);
    if (generationBefore != generationAfter || (generationAfter & 1U) != 0) {
        return false;
    }

    snapshot->generation = generationAfter;
    return true;
}

#endif
