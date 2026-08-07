#include "MirrorAppServer.h"
#include "xstream.h"
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <string.h>
#include "../Utils/PermissionCheckUtils.h"
#include "osxrdp/packet.h"
#include "utils.h"

static const char* kTrustedClientTeamId = "33X7M69J4B";
static const char* kTrustedClientSigningIdentifier = "xrdp";

MirrorAppServer::MirrorAppServer()
: _cmdPipe(NULL)
, _ioThreadStarted(0)
, _state(State_Idle)
, _client(NULL) {
    pthread_mutex_init(&_stateLock, NULL);
    pthread_mutex_init(&_clientLock, NULL);
}

MirrorAppServer::~MirrorAppServer() {
    Stop();
    pthread_mutex_destroy(&_stateLock);
    pthread_mutex_destroy(&_clientLock);
}

void MirrorAppServer::Start() {
    // ignore if server is starting or running
    if (IsState(State_Running) || IsState(State_Starting)) {
        return;
    }
    
    // check required permissions
    if (is_root_process() == 0 && PermissionCheckUtils::HasAllPermissionToStartRemoteConnection() == false) {
        return;
    }
    
    // set to starting
    SetState(State_Starting);
    
    // create IPC server
    if (CreateCommandPipeServer() == false) {
        SetState(State_Idle);
        return;
    }

    // start IO thread
    if (StartIoThread() == false) {
        DestroyCommandPipeServer();
        SetState(State_Idle);
        return;
    }
    
    // change state to Running
    SetState(State_Running);
}

void MirrorAppServer::Stop() {
    if (IsState(State_Idle) || IsState(State_Stopped)) {
        return;
    }
    
    if (IsState(State_Stopping)) {
        // if already stopping, wait for stop
        StopIoThread();
        return;
    }
    
    SetState(State_Stopping);
    
    // signal xipc_loop to exit
    SignalIoThreadToStop();
    
    // wait for IO thread to finish
    StopIoThread();
    
    // cleanup IPC
    DestroyCommandPipeServer();
    
    // finalize state
    SetState(State_Stopped);
}

bool MirrorAppServer::IsRunning() {
    return IsState(State_Running);
}

bool MirrorAppServer::HasConnectedClient() {
    pthread_mutex_lock(&_clientLock);
    bool connected = _client != NULL;
    pthread_mutex_unlock(&_clientLock);
    return connected;
}

bool MirrorAppServer::HasRemoteClipboardFiles() {
    return GetRemoteClipboardFileCount() > 0;
}

int MirrorAppServer::GetRemoteClipboardFileCount() {
    pthread_mutex_lock(&_clientLock);
    int count = 0;
    if (_client != NULL && _client->user_data != NULL) {
        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)_client->user_data;
        if (ctx != NULL && ctx->Clipboard != NULL) {
            count = ctx->Clipboard->RemoteFileCount();
        }
    }
    pthread_mutex_unlock(&_clientLock);
    return count;
}

void MirrorAppServer::StartRemoteClipboardFileCopy() {
    pthread_mutex_lock(&_clientLock);
    if (_client != NULL && _client->user_data != NULL) {
        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)_client->user_data;
        if (ctx != NULL && ctx->Clipboard != NULL) {
            ctx->Clipboard->StartRemoteFileCopy();
        }
    }
    pthread_mutex_unlock(&_clientLock);
}

void MirrorAppServer::StartRemoteClipboardFileCopyToDownloads() {
    pthread_mutex_lock(&_clientLock);
    if (_client != NULL && _client->user_data != NULL) {
        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)_client->user_data;
        if (ctx != NULL && ctx->Clipboard != NULL) {
            ctx->Clipboard->StartRemoteFileCopyToDownloads();
        }
    }
    pthread_mutex_unlock(&_clientLock);
}

bool MirrorAppServer::CreateCommandPipeServer() {
    if (_cmdPipe != NULL) {
        NSLog(@"[MirrorAppServer]::CreateCommandPipeServer cmdPipe already exists.");
        return false;
    }
    
    xipc_t* cmdPipe = xipc_ctx_create(OnMessageReceived, this);
    if (cmdPipe == NULL) {
        NSLog(@"[MirrorAppServer]::CreateCommandPipeServer xipc_ctx_create failed.");
        return false;
    }
    
    char server_path[512];
    
    if (get_object_name_by_sessionid("/tmp/osxrdp", server_path, 512, is_root_process()) == 0) {
        NSLog(@"[MirrorAppServer]::CreateCommandPipeServer get_object_name_by_sessionid failed.");
        xipc_destroy(cmdPipe);
        return false;
    }

    if (xipc_create_server(cmdPipe, server_path, OnClientConnected, OnClientDisconnected, OnClientAuthorize, OnClientRejected) != 0) {
        xipc_destroy(cmdPipe);
        NSLog(@"[MirrorAppServer]::CreateCommandPipeServer xipc_create_server failed. serverName %s", server_path);
        return false;
    }
    
    _cmdPipe = cmdPipe;
    return true;
}

void MirrorAppServer::DestroyCommandPipeServer() {
    if (_cmdPipe == NULL) {
        return;
    }
    
    xipc_destroy(_cmdPipe);
    _cmdPipe = NULL;
}

bool MirrorAppServer::StartIoThread() {
    if (_cmdPipe == NULL) {
        return false;
    }
    
    if (_ioThreadStarted) {
        return true;
    }
    
    // create thread to run IPC socket loop
    int rc = pthread_create(&_ioThread, NULL, &MirrorAppServer::IoThreadEntry, this);
    if (rc != 0) {
        NSLog(@"[MirrorAppServer]::StartIoThread pthread_create failed: %d", rc);
        _ioThreadStarted = 0;
        return false;
    }
    
    NSLog(@"[MirrorAppServer]::StartIoThread");
    
    _ioThreadStarted = 1;
    return true;
}

void MirrorAppServer::StopIoThread() {
    if (_ioThreadStarted) {
        xipc_end_loop(_cmdPipe);
        
        pthread_join(_ioThread, NULL);
        _ioThreadStarted = 0;
    }
}

void MirrorAppServer::SignalIoThreadToStop() {
    if (_cmdPipe == NULL) {
        return;
    }
    
    xipc_end_loop(_cmdPipe);
}

void* MirrorAppServer::IoThreadEntry(void* arg) {
    MirrorAppServer* _this = (MirrorAppServer*)arg;
    if (_this == NULL || _this->_cmdPipe == NULL) {
        return NULL;
    }
    
    xipc_loop(_this->_cmdPipe);
    return NULL;
}

static void TearDownClientCtx(struct MirrorAppClientCtx* ctx) {
    if (ctx == NULL) {
        return;
    }

    if (ctx->ScreenRecorder != NULL) {
        ctx->ScreenRecorder->Stop();
        delete ctx->ScreenRecorder;
        ctx->ScreenRecorder = NULL;
    }

    if (ctx->Clipboard != NULL) {
        ClipboardManager* clipboardToDelete = ctx->Clipboard;
        ctx->Clipboard = NULL;
        dispatch_async(dispatch_get_main_queue(), ^{
            delete clipboardToDelete;
        });
    }

    free(ctx);
}

static void ForceCloseClient(xipc_t* client) {
    if (client == NULL) {
        return;
    }

    client->closed = 1;
    if (client->fd >= 0) {
        close(client->fd);
        client->fd = -1;
    }
}

int MirrorAppServer::OnClientConnected(xipc_t* t, xipc_t* client) {
    @autoreleasepool {
        MirrorAppServer* _this = (MirrorAppServer*)t->user_data;
        
        NSLog(@"[MirrorAppServer::OnClientConnected] new client connected");
        
        pthread_mutex_lock(&_this->_clientLock);
        
        if (_this->_client != NULL) {
            xipc_t* oldClient = _this->_client;
            struct MirrorAppClientCtx* oldCtx = (struct MirrorAppClientCtx*)oldClient->user_data;
            oldClient->user_data = NULL;
            _this->_client = NULL;

            if (oldCtx != NULL && oldCtx->ScreenRecorder != NULL) {
                oldCtx->ScreenRecorder->SendDisconnectMsgToClient();
            }
            TearDownClientCtx(oldCtx);
            ForceCloseClient(oldClient);
        }
        
        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)malloc(sizeof(struct MirrorAppClientCtx));
        if (ctx == NULL) {
            pthread_mutex_unlock(&_this->_clientLock);
            ForceCloseClient(client);
            return 0;
        }

        memset(ctx, 0, sizeof(*ctx));
        ctx->ScreenRecorder = _this->CreateScreenRecorder();
        ctx->Clipboard = new ClipboardManager();
        if (ctx->ScreenRecorder == NULL || ctx->Clipboard == NULL) {
            TearDownClientCtx(ctx);
            pthread_mutex_unlock(&_this->_clientLock);
            ForceCloseClient(client);
            return 0;
        }
        
        client->user_data = (void*)ctx;
        _this->_client = client;
        
        pthread_mutex_unlock(&_this->_clientLock);

        return 0;
    }
}

int MirrorAppServer::OnClientAuthorize(xipc_t* t, xipc_t* client) {
    (void)t;
#if DEBUG
    return 0;
#else
    // Verify client has valid code signature. (Prevents malicious process connections)
    return xipc_is_client_signed_by(client, kTrustedClientTeamId, kTrustedClientSigningIdentifier);
#endif
}

int MirrorAppServer::OnClientRejected(xipc_t* t, xipc_t* client) {
    (void)t;

    pid_t peerPid = 0;
    if (xipc_get_peer_pid(client, &peerPid) == 0) {
        NSLog(@"[MirrorAppServer::OnClientRejected] rejected unauthorized client pid=%d", (int)peerPid);
    }
    else {
        NSLog(@"[MirrorAppServer::OnClientRejected] rejected unauthorized client");
    }

    return 0;
}

int MirrorAppServer::OnClientDisconnected(xipc_t* t, xipc_t* client) {
    @autoreleasepool {
        MirrorAppServer* _this = (MirrorAppServer*)t->user_data;
        NSLog(@"[MirrorAppServer::OnClientDisconnected] client disconnected");
        
        pthread_mutex_lock(&_this->_clientLock);
        if (_this->_client == client) {
            _this->_client = NULL;
        }
        pthread_mutex_unlock(&_this->_clientLock);

        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)client->user_data;
        client->user_data = NULL;
        TearDownClientCtx(ctx);

        return 0;
    }
}

int MirrorAppServer::OnMessageReceived(xipc_t* t, xipc_t* client, void* data, int len) {
    @autoreleasepool {
        if (t == NULL || data == NULL || len <= 0) {
            return 0;
        }
        
        if (client == NULL || client->user_data == NULL) {
            return 0;
        }
        
        struct MirrorAppClientCtx* ctx = (struct MirrorAppClientCtx*)client->user_data;
        
        xstream_t* cmd = xstream_create_for_read(data, len);
        if (cmd == NULL) {
            return 0;
        }
        
        MirrorAppServer* _this = (MirrorAppServer*)t->user_data;
        if (_this == NULL) {
            xstream_free(cmd);
            return 0;
        }
        
        // Ignore commands in Stopping/Stopped state
        bool canHandle = _this->IsState(State_Running);
        if (!canHandle) {
            NSLog(@"[MirrorAppServer::OnMessageReceived] invalid status");

            xstream_free(cmd);
            return 0;
        }
        
        int cmdType = xstream_readInt32(cmd);
            
        switch (cmdType) {
            case OSXRDP_CMDTYPE_SCREEN: {
                ctx->ScreenRecorder->HandleCommand(client, cmd);
                break;
            }
            case OSXRDP_CMDTYPE_CLIPBOARD: {
                ctx->Clipboard->HandleCommand(client, cmd);
                break;
            }
            default:
                break;
        }
        
        xstream_free(cmd);
        return 0;
    }
}

// state access helpers
void MirrorAppServer::SetState(State s) {
    pthread_mutex_lock(&_stateLock);
    _state = s;
    pthread_mutex_unlock(&_stateLock);
}

MirrorAppServer::State MirrorAppServer::GetState() {
    pthread_mutex_lock(&_stateLock);
    State s = _state;
    pthread_mutex_unlock(&_stateLock);
    return s;
}

bool MirrorAppServer::IsState(State s) {
    pthread_mutex_lock(&_stateLock);
    bool same = (_state == s);
    pthread_mutex_unlock(&_stateLock);
    return same;
}

ScreenRecorderManager* MirrorAppServer::CreateScreenRecorder() {
    // ScreenCaptureKit is available from macOS 12.3+ but has bugs, so effectively requires macOS 14+. (filtering bug)
    // So on older OS, legacy API is used for screen recording. (Performance difference is not significant)
    if (@available(macOS 14.0,*)) {
        if (is_root_process() == 1) {
            return new ScreenRecorderManager(true);
        }
        else {
            return new ScreenRecorderManager(false);
        }
    }
    else {
        return new ScreenRecorderManager(true);
    }
}


