#include "harness.h"
#include "../osxup/Paint/InFlightTracker.h"
#include "../osxup/Paint/FrameSelection.h"
#include "../osxup/Paint/CursorSnapshot.h"
#include "osxrdp/screenrecordshm.h"

TEST_CASE(test_push_basic) {
    InFlightTracker t;
    unsigned int frameId = 0;
    EXPECT_TRUE(t.Push(0, 100, &frameId) == true);
    EXPECT_TRUE(frameId > 0);
    EXPECT_EQ_INT(t.TotalCount(), 1);
    EXPECT_EQ_INT(t.CountByDisplay(0), 1);
}

TEST_CASE(test_push_max_per_display) {
    InFlightTracker t;
    unsigned int frameId = 0;

    // Push FRAME_SLOTS (7) frames for display 0
    for (int i = 0; i < FRAME_SLOTS; i++) {
        EXPECT_TRUE(t.Push(0, i * 100, &frameId) == true);
    }
    EXPECT_EQ_INT(t.CountByDisplay(0), FRAME_SLOTS);

    // 8th push should fail
    EXPECT_TRUE(t.Push(0, 700, &frameId) == false);
    EXPECT_EQ_INT(t.CountByDisplay(0), FRAME_SLOTS);
}

TEST_CASE(test_push_invalid_display) {
    InFlightTracker t;
    unsigned int frameId = 0;
    EXPECT_TRUE(t.Push(-1, 0, &frameId) == false);
    EXPECT_TRUE(t.Push(16, 0, &frameId) == false);
    EXPECT_TRUE(t.Push(0, 0, NULL) == false);
}

TEST_CASE(test_pop_acked_cumulative) {
    InFlightTracker t;
    unsigned int frameIds[3];

    for (int i = 0; i < 3; i++) {
        t.Push(0, i * 100, &frameIds[i]);
    }
    EXPECT_EQ_INT(t.TotalCount(), 3);

    // ackFrameId < 0 pops all (cumulative ack)
    unsigned int maxReadPos[16] = {0};
    bool hasReadPos[16] = {false};
    int popped = t.PopAcked(-1, maxReadPos, hasReadPos);
    EXPECT_EQ_INT(popped, 3);
    EXPECT_EQ_INT(t.TotalCount(), 0);
    EXPECT_TRUE(hasReadPos[0] == true);
    // maxReadPos is the maximum acknowledged SHM position.
    EXPECT_EQ_INT((int)maxReadPos[0], 200);
}

TEST_CASE(test_pop_acked_uses_maximum_shm_position) {
    InFlightTracker t;
    unsigned int frameId;
    t.Push(0, 6, &frameId);
    t.Push(0, 1, &frameId);
    t.Push(0, 2, &frameId);

    unsigned int maxReadPos[16] = {0};
    bool hasReadPos[16] = {false};
    EXPECT_EQ_INT(t.PopAcked(-1, maxReadPos, hasReadPos), 3);
    EXPECT_TRUE(hasReadPos[0]);
    EXPECT_EQ_INT(maxReadPos[0], 6);
}

TEST_CASE(test_cancel_latest_and_last_position) {
    InFlightTracker t;
    unsigned int f0, f1;
    unsigned int pos = 0;
    t.Push(0, 10, &f0);
    t.Push(0, 11, &f1);

    EXPECT_TRUE(t.GetLastPositionByDisplay(0, &pos));
    EXPECT_EQ_INT(pos, 11);
    EXPECT_TRUE(t.CancelLatest(f0) == false);
    EXPECT_TRUE(t.CancelLatest(f1));
    EXPECT_EQ_INT(t.CountByDisplay(0), 1);
    EXPECT_TRUE(t.GetLastPositionByDisplay(0, &pos));
    EXPECT_EQ_INT(pos, 10);
}

TEST_CASE(test_pop_acked_partial) {
    InFlightTracker t;
    unsigned int f0, f1, f2;

    t.Push(0, 100, &f0);
    t.Push(0, 200, &f1);
    t.Push(0, 300, &f2);

    // Pop only frames with frameId <= f1
    int popped = t.PopAcked((int)f1, NULL, NULL);
    EXPECT_EQ_INT(popped, 2);
    EXPECT_EQ_INT(t.TotalCount(), 1);
    EXPECT_EQ_INT(t.CountByDisplay(0), 1);
}

TEST_CASE(test_pop_acked_none) {
    InFlightTracker t;
    unsigned int f0;
    t.Push(0, 100, &f0);

    // No frames with frameId <= 0 (first frameId is always > 0)
    int popped = t.PopAcked(0, NULL, NULL);
    EXPECT_EQ_INT(popped, 0);
    EXPECT_EQ_INT(t.TotalCount(), 1);
}

TEST_CASE(test_multi_display) {
    InFlightTracker t;
    unsigned int f0, f1;

    t.Push(0, 100, &f0);
    t.Push(1, 200, &f1);

    EXPECT_EQ_INT(t.CountByDisplay(0), 1);
    EXPECT_EQ_INT(t.CountByDisplay(1), 1);

    // Pop display 0's frame
    t.PopAcked((int)f0, NULL, NULL);
    EXPECT_EQ_INT(t.CountByDisplay(0), 0);
    EXPECT_EQ_INT(t.CountByDisplay(1), 1);
}

TEST_CASE(test_reset) {
    InFlightTracker t;
    unsigned int f;
    t.Push(0, 100, &f);
    t.Push(1, 200, &f);
    t.Push(2, 300, &f);
    EXPECT_EQ_INT(t.TotalCount(), 3);

    t.Reset();
    EXPECT_EQ_INT(t.TotalCount(), 0);
    EXPECT_EQ_INT(t.CountByDisplay(0), 0);
    EXPECT_EQ_INT(t.CountByDisplay(1), 0);
    EXPECT_EQ_INT(t.CountByDisplay(2), 0);

    // Can push again after reset
    EXPECT_TRUE(t.Push(0, 100, &f) == true);
    EXPECT_EQ_INT(t.TotalCount(), 1);
}

TEST_CASE(test_push_after_pop_refill) {
    InFlightTracker t;
    unsigned int f;

    // Fill display 0 to max
    for (int i = 0; i < FRAME_SLOTS; i++) {
        t.Push(0, i * 100, &f);
    }
    // Cannot push more
    EXPECT_TRUE(t.Push(0, 999, &f) == false);

    // Pop all
    t.PopAcked(-1, NULL, NULL);
    EXPECT_EQ_INT(t.TotalCount(), 0);

    // Can push again
    EXPECT_TRUE(t.Push(0, 100, &f) == true);
    EXPECT_EQ_INT(t.TotalCount(), 1);
}

TEST_CASE(test_frame_id_monotonic) {
    InFlightTracker t;
    unsigned int f0, f1, f2;

    t.Push(0, 100, &f0);
    t.Push(0, 200, &f1);
    t.Push(0, 300, &f2);

    EXPECT_TRUE(f1 > f0);
    EXPECT_TRUE(f2 > f1);
}

TEST_CASE(test_frame_selection_chases_latest_then_continues_monotonically) {
    FrameSelectionDecision first =
        SelectFramePosition(0, 5, 0, false, 0, true);
    EXPECT_TRUE(first.hasFrame);
    EXPECT_EQ_INT((int)first.targetPos, 4);
    EXPECT_EQ_INT((int)first.skippedFrames, 4);
    EXPECT_TRUE(first.forceFullDirty);

    FrameSelectionDecision next =
        SelectFramePosition(0, 6, 1, true, first.targetPos, true);
    EXPECT_TRUE(next.hasFrame);
    EXPECT_EQ_INT((int)next.targetPos, 5);
    EXPECT_EQ_INT((int)next.skippedFrames, 0);
}

TEST_CASE(test_frame_selection_rfx_full_backlog_requests_reset) {
    FrameSelectionDecision full =
        SelectFramePosition(3, 3 + FRAME_SLOTS, 0, false, 0, false);
    EXPECT_TRUE(full.hasFrame == false);
    EXPECT_TRUE(full.requestRFXFullRedraw);

    FrameSelectionDecision ordered =
        SelectFramePosition(3, 3 + FRAME_SLOTS - 1, 0, false, 0, false);
    EXPECT_TRUE(ordered.hasFrame);
    EXPECT_TRUE(ordered.requestRFXFullRedraw == false);
    EXPECT_EQ_INT((int)ordered.targetPos, 3);
}

TEST_CASE(test_cursor_snapshot_seqlock_and_continuous_updates) {
    cursor_data_t cursor = {};
    CursorSnapshot snapshot = {};

    atomic_store_explicit(&cursor.generation, 1, memory_order_release);
    EXPECT_TRUE(TryCopyCursorSnapshot(&cursor, 0, &snapshot) == false);

    cursor.width = 2;
    cursor.height = 2;
    cursor.hotspotX = 1;
    cursor.hotspotY = 0;
    cursor.cursorImgDataSize = 16;
    memset(cursor.cursorImgData, 0x5A, 16);
    memset(cursor.cursorMaskData, 0xFF, sizeof(cursor.cursorMaskData));
    atomic_store_explicit(&cursor.generation, 2, memory_order_release);
    EXPECT_TRUE(TryCopyCursorSnapshot(&cursor, 0, &snapshot));
    EXPECT_EQ_INT((int)snapshot.generation, 2);
    EXPECT_EQ_INT(snapshot.image[0], 0x5A);
    EXPECT_TRUE(TryCopyCursorSnapshot(&cursor, 2, &snapshot) == false);

    cursor.cursorImgData[0] = 0x33;
    atomic_store_explicit(&cursor.generation, 4, memory_order_release);
    EXPECT_TRUE(TryCopyCursorSnapshot(&cursor, 2, &snapshot));
    EXPECT_EQ_INT((int)snapshot.generation, 4);
    EXPECT_EQ_INT(snapshot.image[0], 0x33);
}

int main(void) {
    RUN_TEST(test_push_basic);
    RUN_TEST(test_push_max_per_display);
    RUN_TEST(test_push_invalid_display);
    RUN_TEST(test_pop_acked_cumulative);
    RUN_TEST(test_pop_acked_uses_maximum_shm_position);
    RUN_TEST(test_cancel_latest_and_last_position);
    RUN_TEST(test_pop_acked_partial);
    RUN_TEST(test_pop_acked_none);
    RUN_TEST(test_multi_display);
    RUN_TEST(test_reset);
    RUN_TEST(test_push_after_pop_refill);
    RUN_TEST(test_frame_id_monotonic);
    RUN_TEST(test_frame_selection_chases_latest_then_continues_monotonically);
    RUN_TEST(test_frame_selection_rfx_full_backlog_requests_reset);
    RUN_TEST(test_cursor_snapshot_seqlock_and_continuous_updates);
    return test_main_finish("test_inflight_tracker");
}
