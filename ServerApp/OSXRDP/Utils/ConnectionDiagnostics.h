#ifndef ConnectionDiagnostics_h
#define ConnectionDiagnostics_h

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
};

class ConnectionDiagnostics {
public:
    static ConnectionDiagnosticsSnapshot Capture(void);
    static void SetLastStartErrorKey(const char* key);
    static const char* LastStartErrorKey(void);
};

#endif /* __cplusplus */

#endif /* ConnectionDiagnostics_h */
