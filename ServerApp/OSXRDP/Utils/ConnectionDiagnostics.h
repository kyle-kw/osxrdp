#ifndef ConnectionDiagnostics_h
#define ConnectionDiagnostics_h

#include <stdint.h>

#ifdef __cplusplus

struct ConnectionDiagnosticsSnapshot {
    bool accessibilityGranted;
    bool screenRecordingGranted;
    bool agentRunning;
    bool rdpClientConnected;
    bool remoteFilesReady;
    int remoteFileCount;
    // 0=ok, 1=missing_permissions, 2=agent_stopped, 3=start_failed
    int overallState;
    const char* lastStartErrorKey; // localization key or empty
    // Session metrics (feature #11)
    int activeDisplayCount;
    int currentWidth;
    int currentHeight;
    int currentFramerate;
    char currentCodecBuf[32];
    const char* currentCodec; // points at currentCodecBuf (or empty string)
    int frameLag;
    uint64_t totalFramesWritten;
    uint64_t droppedFrames;
    uint64_t copyFailures;
    uint64_t rfxFullRedrawRequests;
    uint64_t imeTimeouts;
};

class ConnectionDiagnostics {
public:
    static ConnectionDiagnosticsSnapshot Capture(void);
    static void SetLastStartErrorKey(const char* key);
    static const char* LastStartErrorKey(void);
};

#endif /* __cplusplus */

#endif /* ConnectionDiagnostics_h */
