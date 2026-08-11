#ifndef osxrdp_stream_policy_h
#define osxrdp_stream_policy_h

#ifdef __cplusplus
extern "C" {
#endif

#define OSXRDP_STREAM_POLICY_VERSION 1
#define OSXRDP_STREAM_QUALITY_DEFAULT OSXRDP_STREAM_QUALITY_HIGH

typedef enum osxrdp_stream_quality_preset {
    OSXRDP_STREAM_QUALITY_HIGH = 0,
    OSXRDP_STREAM_QUALITY_HOTSPOT = 1,
    OSXRDP_STREAM_QUALITY_EXTREME_SAVER = 2
} osxrdp_stream_quality_preset_t;

typedef struct osxrdp_stream_policy {
    int preset;
    int framerate;
    int targetBitrate;
    int maximumBitrate;
    int keyframeIntervalSeconds;
    int maximumPendingFrames;
    int usesAgentH264;
    int allowsMultipleMonitors;
} osxrdp_stream_policy_t;

#define OSXRDP_STREAM_TAIL_OK 1
#define OSXRDP_STREAM_TAIL_TRUNCATED 0
#define OSXRDP_STREAM_TAIL_UNKNOWN_VERSION (-1)

#define OSXRDP_STREAM_POLICY_ALLOWED 1
#define OSXRDP_STREAM_POLICY_REQUIRES_H264 0
#define OSXRDP_STREAM_POLICY_REJECTS_MULTIMONITOR (-1)

#define OSXRDP_ENCODER_ACTION_RETRY_VIDEOTOOLBOX 1
#define OSXRDP_ENCODER_ACTION_RECONFIGURE_OPENH264 2
#define OSXRDP_ENCODER_ACTION_TERMINATE 3

static inline int osxrdp_stream_quality_is_valid(int preset) {
    return preset >= OSXRDP_STREAM_QUALITY_HIGH &&
           preset <= OSXRDP_STREAM_QUALITY_EXTREME_SAVER;
}

static inline int osxrdp_stream_policy_resolve(int preset,
                                               osxrdp_stream_policy_t* policy) {
    if (policy == 0) {
        return 0;
    }
    if (!osxrdp_stream_quality_is_valid(preset)) {
        preset = OSXRDP_STREAM_QUALITY_DEFAULT;
    }

    policy->preset = preset;
    policy->keyframeIntervalSeconds = 5;
    policy->allowsMultipleMonitors = preset == OSXRDP_STREAM_QUALITY_HIGH;
    policy->usesAgentH264 = preset != OSXRDP_STREAM_QUALITY_HIGH;
    switch (preset) {
        case OSXRDP_STREAM_QUALITY_HOTSPOT:
            policy->framerate = 24;
            policy->targetBitrate = 2500000;
            policy->maximumBitrate = 3500000;
            policy->maximumPendingFrames = 2;
            break;
        case OSXRDP_STREAM_QUALITY_EXTREME_SAVER:
            policy->framerate = 15;
            policy->targetBitrate = 1000000;
            policy->maximumBitrate = 1500000;
            policy->maximumPendingFrames = 1;
            break;
        default:
            policy->framerate = 60;
            policy->targetBitrate = 0;
            policy->maximumBitrate = 0;
            policy->keyframeIntervalSeconds = 0;
            policy->maximumPendingFrames = 0;
            break;
    }
    return 1;
}

static inline int osxrdp_stream_policy_parse_tail(int remainingBytes,
                                                  int version, int preset,
                                                  int* resolvedPreset) {
    if (resolvedPreset == 0) return OSXRDP_STREAM_TAIL_TRUNCATED;
    if (remainingBytes == 0) {
        *resolvedPreset = OSXRDP_STREAM_QUALITY_HIGH;
        return OSXRDP_STREAM_TAIL_OK;
    }
    if (remainingBytes != (int)(sizeof(int) * 2) ||
        !osxrdp_stream_quality_is_valid(preset)) {
        return OSXRDP_STREAM_TAIL_TRUNCATED;
    }
    if (version != OSXRDP_STREAM_POLICY_VERSION) {
        return OSXRDP_STREAM_TAIL_UNKNOWN_VERSION;
    }
    *resolvedPreset = preset;
    return OSXRDP_STREAM_TAIL_OK;
}

static inline int osxrdp_stream_policy_validate_connection(
        const osxrdp_stream_policy_t* policy, int hasH264, int monitorCount) {
    if (policy == 0 || !policy->usesAgentH264) return OSXRDP_STREAM_POLICY_ALLOWED;
    if (!hasH264) return OSXRDP_STREAM_POLICY_REQUIRES_H264;
    if (monitorCount > 1) return OSXRDP_STREAM_POLICY_REJECTS_MULTIMONITOR;
    return OSXRDP_STREAM_POLICY_ALLOWED;
}

static inline int osxrdp_encoder_failure_action(int consecutiveFailures,
                                                int openH264FallbackActive) {
    if (openH264FallbackActive) return OSXRDP_ENCODER_ACTION_TERMINATE;
    return consecutiveFailures <= 1
        ? OSXRDP_ENCODER_ACTION_RETRY_VIDEOTOOLBOX
        : OSXRDP_ENCODER_ACTION_RECONFIGURE_OPENH264;
}

#ifdef __cplusplus
}
#endif

#endif /* osxrdp_stream_policy_h */
