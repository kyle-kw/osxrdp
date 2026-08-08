#include "RemoteConnectionService.h"

#include "../MirrorAppServer/MirrorAppServer.h"
#include "../Utils/ConnectionDiagnostics.h"
#include "../Utils/PermissionCheckUtils.h"

static MirrorAppServer* g_server = nullptr;

bool StartRemoteConnectionServerService(void) {
    if (g_server != nullptr) {
        if (g_server->IsRunning()) {
            return true;
        }
        // Stale instance in a non-running state: tear down so start can rebuild.
        g_server->Stop();
        delete g_server;
        g_server = nullptr;
    }

    if (PermissionCheckUtils::HasAllPermissionToStartRemoteConnection() == false) {
        ConnectionDiagnostics::SetLastStartErrorKey("diag.error.missing_permissions");
        return false;
    }

    g_server = new MirrorAppServer();
    g_server->Start();
    if (!g_server->IsRunning()) {
        delete g_server;
        g_server = nullptr;
        ConnectionDiagnostics::SetLastStartErrorKey("diag.error.agent_start_failed");
        return false;
    }

    ConnectionDiagnostics::SetLastStartErrorKey(NULL);
    return true;
}

void StopRemoteConnectionServerService(void) {
    if (g_server == nullptr) {
        ConnectionDiagnostics::SetLastStartErrorKey(NULL);
        return;
    }

    g_server->Stop();
    delete g_server;
    g_server = nullptr;
    ConnectionDiagnostics::SetLastStartErrorKey(NULL);
}

bool IsRemoteConnectionServerServiceRunning(void) {
    return g_server != nullptr && g_server->IsRunning();
}

bool IsRemoteRdpClientConnected(void) {
    return g_server != nullptr && g_server->HasConnectedClient();
}

bool HasRemoteClipboardFiles(void) {
    return g_server != nullptr && g_server->HasRemoteClipboardFiles();
}

int GetRemoteClipboardFileCount(void) {
    if (g_server == nullptr) {
        return 0;
    }
    return g_server->GetRemoteClipboardFileCount();
}

void StartRemoteClipboardFileCopy(void) {
    if (g_server == nullptr) {
        return;
    }

    g_server->StartRemoteClipboardFileCopy();
}

void StartRemoteClipboardFileCopyToDownloads(void) {
    if (g_server == nullptr) {
        return;
    }

    g_server->StartRemoteClipboardFileCopyToDownloads();
}
