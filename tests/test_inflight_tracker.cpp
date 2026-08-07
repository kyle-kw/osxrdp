#include "harness.h"
#include "../osxup/Paint/InFlightTracker.h"
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
    // maxReadPos should be the last pushed value (FIFO order, each overwrites)
    EXPECT_EQ_INT((int)maxReadPos[0], 200);
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

int main(void) {
    RUN_TEST(test_push_basic);
    RUN_TEST(test_push_max_per_display);
    RUN_TEST(test_push_invalid_display);
    RUN_TEST(test_pop_acked_cumulative);
    RUN_TEST(test_pop_acked_partial);
    RUN_TEST(test_pop_acked_none);
    RUN_TEST(test_multi_display);
    RUN_TEST(test_reset);
    RUN_TEST(test_push_after_pop_refill);
    RUN_TEST(test_frame_id_monotonic);
    return test_main_finish("test_inflight_tracker");
}
