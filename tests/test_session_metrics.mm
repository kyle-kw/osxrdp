#include "harness.h"
#import "Utils/SessionMetrics.h"

TEST_CASE(negative_wall_clock_does_not_produce_a_bitrate_bucket) {
    EXPECT_EQ_INT(SessionMetricsBitrateBucketForSecond((time_t)-1), -1);
    EXPECT_EQ_INT(SessionMetricsBitrateBucketForSecond((time_t)-100), -1);
}

TEST_CASE(nonnegative_wall_clock_wraps_across_five_buckets) {
    EXPECT_EQ_INT(SessionMetricsBitrateBucketForSecond((time_t)0), 0);
    EXPECT_EQ_INT(SessionMetricsBitrateBucketForSecond((time_t)4), 4);
    EXPECT_EQ_INT(SessionMetricsBitrateBucketForSecond((time_t)5), 0);
}

int main(void) {
    RUN_TEST(negative_wall_clock_does_not_produce_a_bitrate_bucket);
    RUN_TEST(nonnegative_wall_clock_wraps_across_five_buckets);
    return test_main_finish("test_session_metrics");
}
