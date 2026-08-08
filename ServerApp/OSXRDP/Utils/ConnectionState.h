#ifndef ConnectionState_h
#define ConnectionState_h

enum class ConnectionState {
    NeedsPermissions = 0,
    Starting,
    Ready,
    Connected,
    Stopped,
    Failed,
};

enum class ConnectionPrimaryAction {
    None = 0,
    SetUpPermissions,
    StartService,
    StopService,
    Retry,
};

ConnectionState ConnectionStateResolve(bool accessibilityGranted,
                                       bool screenRecordingGranted,
                                       bool agentRunning,
                                       bool rdpClientConnected,
                                       bool starting,
                                       bool hasStartError);

ConnectionPrimaryAction ConnectionPrimaryActionForState(ConnectionState state);

bool ConnectionDesiredRunningFromStoredValue(bool hasStoredValue,
                                             bool storedValue);

bool ConnectionShouldStartOnLaunch(bool desiredRunning,
                                   bool permissionsGranted,
                                   bool agentRunning);

bool ConnectionShouldAutoStartAfterRefresh(bool desiredRunning,
                                           bool hadPermissions,
                                           bool permissionsGranted,
                                           bool agentRunning,
                                           bool starting);

#endif /* ConnectionState_h */
