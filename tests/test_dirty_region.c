#include "harness.h"
#include "osxrdp/dirty_region.h"

TEST_CASE(empty_addition_does_not_create_full_frame) {
    struct RECT rects[MAX_DIRTY_COUNT] = {{0}};
    int count = 0;
    EXPECT_EQ_INT(osxrdp_dirty_region_merge(rects, &count, NULL, 0, 1920, 1080),
                  OSXRDP_DIRTY_MERGE_EMPTY);
    EXPECT_EQ_INT(count, 0);
}

TEST_CASE(overflow_rasterizes_and_merges_adjacent_tiles) {
    struct RECT rects[MAX_DIRTY_COUNT] = {{0}};
    struct RECT additions[MAX_DIRTY_COUNT] = {{0}};
    int count = MAX_DIRTY_COUNT;
    for (int i = 0; i < MAX_DIRTY_COUNT; ++i) {
        rects[i] = (struct RECT){(short)(i % 16 * 4), (short)(i / 16 * 4), 2, 2};
        additions[i] = (struct RECT){(short)(64 + i % 16 * 4), (short)(i / 16 * 4), 2, 2};
    }
    EXPECT_EQ_INT(osxrdp_dirty_region_merge(rects, &count, additions,
                  MAX_DIRTY_COUNT, 1920, 1080), OSXRDP_DIRTY_MERGE_DIRTY);
    EXPECT_TRUE(count > 0 && count < MAX_DIRTY_COUNT);
    EXPECT_TRUE(rects[0].width >= 128);
}

TEST_CASE(tile_result_overflow_collapses_to_one_bounding_rect) {
    struct RECT rects[MAX_DIRTY_COUNT] = {{0}};
    struct RECT additions[400] = {{0}};
    int additionCount = 0;
    for (int row = 0; row < 20; ++row) {
        for (int column = row % 2; column < 40; column += 2) {
            additions[additionCount++] = (struct RECT){
                (short)(column * 64), (short)(row * 64), 1, 1
            };
        }
    }
    int count = 0;
    EXPECT_EQ_INT(osxrdp_dirty_region_merge(rects, &count, additions,
                  additionCount, 2560, 1280), OSXRDP_DIRTY_MERGE_DIRTY);
    EXPECT_EQ_INT(count, 1);
    EXPECT_EQ_INT(rects[0].x, 0);
    EXPECT_EQ_INT(rects[0].y, 0);
    EXPECT_TRUE(rects[0].width >= 2496);
    EXPECT_EQ_INT(rects[0].height, 1280);
}

int main(void) {
    RUN_TEST(empty_addition_does_not_create_full_frame);
    RUN_TEST(overflow_rasterizes_and_merges_adjacent_tiles);
    RUN_TEST(tile_result_overflow_collapses_to_one_bounding_rect);
    return test_main_finish("test_dirty_region");
}
