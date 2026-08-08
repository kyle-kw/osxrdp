#include "ConnectionState.h"

ConnectionState ConnectionStateResolve(bool accessibilityGranted,
                                       bool screenRecordingGranted,
                                       bool agentRunning,
                                       bool rdpClientConnected,
                                       bool starting,
                                       bool hasStartError) {
    if (!accessibilityGranted || !screenRecordingGranted) {
        return ConnectionState::NeedsPermissions;
    }
    if (starting) {
        return ConnectionState::Starting;
    }
    if (agentRunning) {
        return rdpClientConnected ? ConnectionState::Connected : ConnectionState::Ready;
    }
    if (hasStartError) {
        return ConnectionState::Failed;
    }
    return ConnectionState::Stopped;
}

ConnectionPrimaryAction ConnectionPrimaryActionForState(ConnectionState state) {
    switch (state) {
        case ConnectionState::NeedsPermissions:
            return ConnectionPrimaryAction::SetUpPermissions;
        case ConnectionState::Starting:
            return ConnectionPrimaryAction::None;
        case ConnectionState::Ready:
        case ConnectionState::Connected:
            return ConnectionPrimaryAction::StopService;
        case ConnectionState::Stopped:
            return ConnectionPrimaryAction::StartService;
        case ConnectionState::Failed:
            return ConnectionPrimaryAction::Retry;
    }
}

bool ConnectionDesiredRunningFromStoredValue(bool hasStoredValue,
                                             bool storedValue) {
    return hasStoredValue ? storedValue : true;
}

bool ConnectionShouldStartOnLaunch(bool desiredRunning,
                                   bool permissionsGranted,
                                   bool agentRunning) {
    return desiredRunning && permissionsGranted && !agentRunning;
}

bool ConnectionShouldAutoStartAfterRefresh(bool desiredRunning,
                                           bool hadPermissions,
                                           bool permissionsGranted,
                                           bool agentRunning,
                                           bool starting) {
    return desiredRunning && !hadPermissions && permissionsGranted && !agentRunning && !starting;
}
