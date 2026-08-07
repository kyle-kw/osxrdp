#include "RemoteConnectionService.h"

#include "../MirrorAppServer/MirrorAppServer.h"

static MirrorAppServer* g_server = nullptr;

bool StartRemoteConnectionServerService(void) {
    if (g_server != nullptr) {
        return false;
    }

    g_server = new MirrorAppServer();
    g_server->Start();
    if (!g_server->IsRunning()) {
        delete g_server;
        g_server = nullptr;
        return false;
    }

    return true;
}

void StopRemoteConnectionServerService(void) {
    if (g_server == nullptr) {
        return;
    }

    g_server->Stop();
    delete g_server;
    g_server = nullptr;
}

bool IsRemoteConnectionServerServiceRunning(void) {
    return g_server != nullptr && g_server->IsRunning();
}

bool HasRemoteClipboardFiles(void) {
    return g_server != nullptr && g_server->HasRemoteClipboardFiles();
}

void StartRemoteClipboardFileCopy(void) {
    if (g_server == nullptr) {
        return;
    }

    g_server->StartRemoteClipboardFileCopy();
}
