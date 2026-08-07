#include "ConnectionDiagnostics.h"
#include "SessionMetrics.h"
#include "PermissionCheckUtils.h"
#include "../RemoteConnection/RemoteConnectionService.h"

#include <stdint.h>
#include <string.h>

static char g_lastStartErrorKey[128] = {0};

void ConnectionDiagnostics::SetLastStartErrorKey(const char* key) {
    if (key == NULL || key[0] == '\0') {
        g_lastStartErrorKey[0] = '\0';
        return;
    }
    strncpy(g_lastStartErrorKey, key, sizeof(g_lastStartErrorKey) - 1);
    g_lastStartErrorKey[sizeof(g_lastStartErrorKey) - 1] = '\0';
}

const char* ConnectionDiagnostics::LastStartErrorKey(void) {
    return g_lastStartErrorKey;
}

ConnectionDiagnosticsSnapshot ConnectionDiagnostics::Capture(void) {
    ConnectionDiagnosticsSnapshot s = {};
    s.accessibilityGranted = PermissionCheckUtils::HasAccPermission();
    s.screenRecordingGranted = PermissionCheckUtils::HasScreenRecordPermission();
    s.agentRunning = IsRemoteConnectionServerServiceRunning();
    s.rdpClientConnected = IsRemoteRdpClientConnected();
    s.remoteFileCount = GetRemoteClipboardFileCount();
    s.remoteFilesReady = s.remoteFileCount > 0;
    // Session metrics (feature #11) — codec lives in snapshot-owned buffer.
    s.currentCodecBuf[0] = '\0';
    SessionMetricsGetSnapshot(&s.activeDisplayCount, &s.currentWidth, &s.currentHeight,
                              &s.currentFramerate, s.currentCodecBuf, sizeof(s.currentCodecBuf),
                              &s.frameLag, &s.totalFramesWritten, &s.droppedFrames);
    s.currentCodec = s.currentCodecBuf;
    s.lastStartErrorKey = g_lastStartErrorKey[0] != '\0' ? g_lastStartErrorKey : "";

    if (s.accessibilityGranted == false || s.screenRecordingGranted == false) {
        s.overallState = 1; // missing permissions
    } else if (s.agentRunning == false) {
        s.overallState = (g_lastStartErrorKey[0] != '\0') ? 3 : 2; // failed or stopped
    } else {
        s.overallState = 0;
    }
    return s;
}
