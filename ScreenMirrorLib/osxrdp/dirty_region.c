#include "dirty_region.h"

#include <stdlib.h>
#include <string.h>

#define TILE_SIZE 64

static int clamp_int(int value, int minimum, int maximum) {
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

static void mark_rect(unsigned char* tiles, int columns, int rows,
                      const struct RECT* rect, int width, int height) {
    int left = clamp_int(rect->x, 0, width);
    int top = clamp_int(rect->y, 0, height);
    int right = clamp_int(rect->x + rect->width, 0, width);
    int bottom = clamp_int(rect->y + rect->height, 0, height);
    if (right <= left || bottom <= top) return;
    int firstColumn = left / TILE_SIZE;
    int lastColumn = (right + TILE_SIZE - 1) / TILE_SIZE;
    int firstRow = top / TILE_SIZE;
    int lastRow = (bottom + TILE_SIZE - 1) / TILE_SIZE;
    for (int row = firstRow; row < lastRow && row < rows; ++row) {
        for (int column = firstColumn; column < lastColumn && column < columns; ++column) {
            tiles[row * columns + column] = 1;
        }
    }
}

static int collapse_tiles_to_bounds(const unsigned char* tiles, int columns, int rows,
                                    int width, int height, struct RECT* rects,
                                    int* rectCount) {
    int firstColumn = columns;
    int firstRow = rows;
    int lastColumn = -1;
    int lastRow = -1;
    for (int row = 0; row < rows; ++row) {
        for (int column = 0; column < columns; ++column) {
            if (!tiles[row * columns + column]) continue;
            if (column < firstColumn) firstColumn = column;
            if (column > lastColumn) lastColumn = column;
            if (row < firstRow) firstRow = row;
            if (row > lastRow) lastRow = row;
        }
    }
    if (lastColumn < firstColumn || lastRow < firstRow) {
        *rectCount = 0;
        return OSXRDP_DIRTY_MERGE_EMPTY;
    }
    int left = firstColumn * TILE_SIZE;
    int top = firstRow * TILE_SIZE;
    int right = (lastColumn + 1) * TILE_SIZE;
    int bottom = (lastRow + 1) * TILE_SIZE;
    if (right > width) right = width;
    if (bottom > height) bottom = height;
    rects[0].x = (short)left;
    rects[0].y = (short)top;
    rects[0].width = (short)(right - left);
    rects[0].height = (short)(bottom - top);
    *rectCount = 1;
    return OSXRDP_DIRTY_MERGE_DIRTY;
}

int osxrdp_dirty_region_merge(struct RECT* rects, int* rectCount,
                              const struct RECT* additions, int additionCount,
                              int width, int height) {
    if (rects == NULL || rectCount == NULL || *rectCount < 0 ||
        *rectCount > MAX_DIRTY_COUNT || additionCount < 0 ||
        width <= 0 || height <= 0) return OSXRDP_DIRTY_MERGE_FULL;
    if (additionCount == 0) {
        return *rectCount == 0 ? OSXRDP_DIRTY_MERGE_EMPTY : OSXRDP_DIRTY_MERGE_DIRTY;
    }
    if (additions == NULL) return OSXRDP_DIRTY_MERGE_FULL;
    if (additionCount <= MAX_DIRTY_COUNT - *rectCount) {
        memcpy(rects + *rectCount, additions, sizeof(struct RECT) * additionCount);
        *rectCount += additionCount;
        return OSXRDP_DIRTY_MERGE_DIRTY;
    }

    int columns = (width + TILE_SIZE - 1) / TILE_SIZE;
    int rows = (height + TILE_SIZE - 1) / TILE_SIZE;
    if (columns <= 0 || rows <= 0 || columns > 10000 || rows > 10000 ||
        (size_t)columns > SIZE_MAX / (size_t)rows) {
        *rectCount = 0;
        return OSXRDP_DIRTY_MERGE_FULL;
    }
    unsigned char* tiles = (unsigned char*)calloc((size_t)columns * rows, 1);
    if (tiles == NULL) {
        *rectCount = 0;
        return OSXRDP_DIRTY_MERGE_FULL;
    }
    for (int i = 0; i < *rectCount; ++i) mark_rect(tiles, columns, rows, &rects[i], width, height);
    for (int i = 0; i < additionCount; ++i) mark_rect(tiles, columns, rows, &additions[i], width, height);

    struct RECT merged[MAX_DIRTY_COUNT];
    int mergedCount = 0;
    for (int row = 0; row < rows; ++row) {
        int column = 0;
        while (column < columns) {
            while (column < columns && !tiles[row * columns + column]) ++column;
            if (column >= columns) break;
            int firstColumn = column;
            while (column < columns && tiles[row * columns + column]) ++column;
            int x = firstColumn * TILE_SIZE;
            int runWidth = column * TILE_SIZE - x;
            if (x + runWidth > width) runWidth = width - x;
            int rowHeight = (row + 1) * TILE_SIZE > height ? height - row * TILE_SIZE : TILE_SIZE;
            int extended = 0;
            for (int i = 0; i < mergedCount; ++i) {
                if (merged[i].x == x && merged[i].width == runWidth &&
                    merged[i].y + merged[i].height == row * TILE_SIZE) {
                    merged[i].height += rowHeight;
                    extended = 1;
                    break;
                }
            }
            if (!extended) {
                if (mergedCount >= MAX_DIRTY_COUNT) {
                    int result = collapse_tiles_to_bounds(tiles, columns, rows,
                        width, height, rects, rectCount);
                    free(tiles);
                    return result;
                }
                merged[mergedCount].x = (short)x;
                merged[mergedCount].y = (short)(row * TILE_SIZE);
                merged[mergedCount].width = (short)runWidth;
                merged[mergedCount].height = (short)rowHeight;
                ++mergedCount;
            }
        }
    }
    free(tiles);
    memcpy(rects, merged, sizeof(struct RECT) * mergedCount);
    *rectCount = mergedCount;
    return mergedCount == 0 ? OSXRDP_DIRTY_MERGE_EMPTY : OSXRDP_DIRTY_MERGE_DIRTY;
}
