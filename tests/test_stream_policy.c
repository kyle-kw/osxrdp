#include "harness.h"
#include "osxrdp/stream_policy.h"
#include "osxrdp/packet.h"

TEST_CASE(presets_map_to_expected_limits) {
    osxrdp_stream_policy_t policy;
    EXPECT_TRUE(osxrdp_stream_policy_resolve(OSXRDP_STREAM_QUALITY_HIGH, &policy));
    EXPECT_EQ_INT(policy.framerate, 60);
    EXPECT_EQ_INT(policy.usesAgentH264, 0);
    EXPECT_EQ_INT(policy.allowsMultipleMonitors, 1);

    EXPECT_TRUE(osxrdp_stream_policy_resolve(OSXRDP_STREAM_QUALITY_HOTSPOT, &policy));
    EXPECT_EQ_INT(policy.framerate, 24);
    EXPECT_EQ_INT(policy.targetBitrate, 2500000);
    EXPECT_EQ_INT(policy.maximumBitrate, 3500000);
    EXPECT_EQ_INT(policy.maximumPendingFrames, 2);

    EXPECT_TRUE(osxrdp_stream_policy_resolve(OSXRDP_STREAM_QUALITY_EXTREME_SAVER, &policy));
    EXPECT_EQ_INT(policy.framerate, 15);
    EXPECT_EQ_INT(policy.targetBitrate, 1000000);
    EXPECT_EQ_INT(policy.maximumBitrate, 1500000);
    EXPECT_EQ_INT(policy.maximumPendingFrames, 1);
}

TEST_CASE(invalid_preset_falls_back_to_high_quality) {
    osxrdp_stream_policy_t policy;
    EXPECT_TRUE(osxrdp_stream_policy_resolve(-1, &policy));
    EXPECT_EQ_INT(policy.preset, OSXRDP_STREAM_QUALITY_HIGH);
    EXPECT_TRUE(osxrdp_stream_policy_resolve(99, &policy));
    EXPECT_EQ_INT(policy.preset, OSXRDP_STREAM_QUALITY_HIGH);
}

TEST_CASE(protocol_tail_accepts_legacy_and_rejects_truncation) {
    int preset = -1;
    EXPECT_EQ_INT(osxrdp_stream_policy_parse_tail(0, 0, 0, &preset), OSXRDP_STREAM_TAIL_OK);
    EXPECT_EQ_INT(preset, OSXRDP_STREAM_QUALITY_HIGH);
    EXPECT_EQ_INT(osxrdp_stream_policy_parse_tail(8, 1, OSXRDP_STREAM_QUALITY_HOTSPOT, &preset), OSXRDP_STREAM_TAIL_OK);
    EXPECT_EQ_INT(preset, OSXRDP_STREAM_QUALITY_HOTSPOT);
    EXPECT_EQ_INT(osxrdp_stream_policy_parse_tail(4, 1, OSXRDP_STREAM_QUALITY_HOTSPOT, &preset), OSXRDP_STREAM_TAIL_TRUNCATED);
    EXPECT_EQ_INT(osxrdp_stream_policy_parse_tail(8, 2, OSXRDP_STREAM_QUALITY_HOTSPOT, &preset), OSXRDP_STREAM_TAIL_UNKNOWN_VERSION);
    EXPECT_EQ_INT(osxrdp_stream_policy_parse_tail(8, 1, 99, &preset), OSXRDP_STREAM_TAIL_TRUNCATED);
}

TEST_CASE(saver_connection_requires_h264_and_one_monitor) {
    osxrdp_stream_policy_t policy;
    osxrdp_stream_policy_resolve(OSXRDP_STREAM_QUALITY_HOTSPOT, &policy);
    EXPECT_EQ_INT(osxrdp_stream_policy_validate_connection(&policy, 0, 1), OSXRDP_STREAM_POLICY_REQUIRES_H264);
    EXPECT_EQ_INT(osxrdp_stream_policy_validate_connection(&policy, 1, 2), OSXRDP_STREAM_POLICY_REJECTS_MULTIMONITOR);
    EXPECT_EQ_INT(osxrdp_stream_policy_validate_connection(&policy, 1, 1), OSXRDP_STREAM_POLICY_ALLOWED);
}

TEST_CASE(already_compressed_flag_preserves_surface_id) {
    EXPECT_EQ_INT(osxrdp_gfx_h264_surface_flags(3, 0), 0x30000000);
    EXPECT_EQ_INT(osxrdp_gfx_h264_surface_flags(3, 1), 0x30000001);
}

TEST_CASE(encoder_failure_state_machine_retries_then_falls_back) {
    EXPECT_EQ_INT(osxrdp_encoder_failure_action(1, 0),
                  OSXRDP_ENCODER_ACTION_RETRY_VIDEOTOOLBOX);
    EXPECT_EQ_INT(osxrdp_encoder_failure_action(2, 0),
                  OSXRDP_ENCODER_ACTION_RECONFIGURE_OPENH264);
    EXPECT_EQ_INT(osxrdp_encoder_failure_action(1, 1),
                  OSXRDP_ENCODER_ACTION_TERMINATE);
}

int main(void) {
    RUN_TEST(presets_map_to_expected_limits);
    RUN_TEST(invalid_preset_falls_back_to_high_quality);
    RUN_TEST(protocol_tail_accepts_legacy_and_rejects_truncation);
    RUN_TEST(saver_connection_requires_h264_and_one_monitor);
    RUN_TEST(already_compressed_flag_preserves_surface_id);
    RUN_TEST(encoder_failure_state_machine_retries_then_falls_back);
    return test_main_finish("test_stream_policy");
}
