#include "../pch.h"
#include "SessionManagerServer.h"
#import <Foundation/Foundation.h>

#include "xstream.h"
#include "osxrdp/packet.h"
#include "utils.h"
#include "sessionmanager.h"

static const char* kTrustedClientTeamId = "33X7M69J4B";
static const char* kTrustedClientSigningIdentifier = "xrdp";

SessionManagerServer::SessionManagerServer()
: _cmdPipe(NULL)
, _ioThreadStarted(0)
, _state(State_Idle) {
    pthread_mutex_init(&_stateLock, NULL);
}

SessionManagerServer::~SessionManagerServer() {
    Stop();
    pthread_mutex_destroy(&_stateLock);
}

void SessionManagerServer::Start() {
    // Ignore if server is starting or running
    if (IsState(State_Running) || IsState(State_Starting)) {
        return;
    }
    
    // Set to starting
    SetState(State_Starting);
    
    // Create IPC server
    if (CreateCommandPipeServer() == false) {
        SetState(State_Idle);
        return;
    }

    // Start IO thread
    if (StartIoThread() == false) {
        DestroyCommandPipeServer();
        SetState(State_Idle);
        return;
    }
    
    // Change state to Running
    SetState(State_Running);
}

void SessionManagerServer::Stop() {
    if (IsState(State_Idle) || IsState(State_Stopped)) {
        return;
    }
    
    if (IsState(State_Stopping)) {
        // If already stopping, wait for stop
        StopIoThread();
        return;
    }
    
    SetState(State_Stopping);
    
    // Signal xipc_loop to exit
    SignalIoThreadToStop();
    
    // Wait for IO thread to finish
    StopIoThread();
    
    // Cleanup IPC
    DestroyCommandPipeServer();
    
    // Finalize state
    SetState(State_Stopped);
}

bool SessionManagerServer::IsRunning() {
    return IsState(State_Running);
}

bool SessionManagerServer::CreateCommandPipeServer() {
    if (_cmdPipe != NULL) {
        dzlog_error("[SessionManagerServer]::CreateCommandPipeServer cmdPipe already exists.");
        return false;
    }
    
    xipc_t* cmdPipe = xipc_ctx_create(OnMessageReceived, this);
    if (cmdPipe == NULL) {
        dzlog_error("[SessionManagerServer]::CreateCommandPipeServer xipc_ctx_create failed.");
        return false;
    }
    
    if (xipc_create_server(cmdPipe, "/tmp/osxrdpsessionmanager", NULL, NULL, OnClientAuthorize, OnClientRejected) != 0) {
        xipc_destroy(cmdPipe);
        dzlog_error("[SessionManagerServer]::CreateCommandPipeServer xipc_create_server failed.");
        return false;
    }
    
    _cmdPipe = cmdPipe;
    return true;
}

void SessionManagerServer::DestroyCommandPipeServer() {
    if (_cmdPipe == NULL) {
        return;
    }
    
    xipc_destroy(_cmdPipe);
    _cmdPipe = NULL;
}

bool SessionManagerServer::StartIoThread() {
    if (_cmdPipe == NULL) {
        return false;
    }
    
    if (_ioThreadStarted) {
        return true;
    }
    
    // Create thread to run IPC socket loop
    int rc = pthread_create(&_ioThread, NULL, &SessionManagerServer::IoThreadEntry, this);
    if (rc != 0) {
        dzlog_error("[SessionManagerServer]::StartIoThread pthread_create failed: %d", rc);
        _ioThreadStarted = 0;
        return false;
    }
    
    _ioThreadStarted = 1;
    return true;
}

void SessionManagerServer::StopIoThread() {
    if (_ioThreadStarted) {
        xipc_end_loop(_cmdPipe);
        
        pthread_join(_ioThread, NULL);
        _ioThreadStarted = 0;
    }
}

void SessionManagerServer::SignalIoThreadToStop() {
    if (_cmdPipe == NULL) {
        return;
    }
    
    xipc_end_loop(_cmdPipe);
}

void* SessionManagerServer::IoThreadEntry(void* arg) {
    SessionManagerServer* _this = (SessionManagerServer*)arg;
    if (_this == NULL || _this->_cmdPipe == NULL) {
        return NULL;
    }
    
    xipc_loop(_this->_cmdPipe);
    return NULL;
}

int SessionManagerServer::OnMessageReceived(xipc_t* t, xipc_t* client, void* data, int len) {
    if (t == NULL || data == NULL || len <= 0) {
        return 0;
    }
    
    if (client == NULL) {
        return 0;
    }
        
    xstream_t* cmd = xstream_create_for_read(data, len);
    if (cmd == NULL) {
        return 0;
    }
    
    SessionManagerServer* _this = (SessionManagerServer*)t->user_data;
    if (_this == NULL) {
        xstream_free(cmd);
        return 0;
    }
    
    // Ignore commands in Stopping/Stopped state
    bool canHandle = _this->IsState(State_Running);
    if (!canHandle) {
        xstream_free(cmd);
        return 0;
    }
    
    int cmdType = xstream_readInt32(cmd);
    switch (cmdType) {
        case OSXRDP_SESSMAN_REQUEST_SESSION: {
            session_info_t sessionInfo = {0,};
            
            const char* username = xstream_readStr(cmd, NULL);
            if (osxrdp_sessionmanager_getsessioninfo(username, &sessionInfo) != 0) {
                // No session for the connecting user
                // Create session and send info to osxup
                if (osxrdp_sessionmanager_createsession(&sessionInfo) != 0) {
                    // Failed to create session
                    sessionInfo.sessionId = -1;
                }
            }
            
            // Send info back to osxup
            xstream* result = xstream_create(32);
            if (result != NULL) {
                xstream_writeInt32(result, OSXRDP_SESSMAN_REPLY_SESSION);
                xstream_writeInt32(result, sessionInfo.sessionId);
                xstream_writeInt32(result, sessionInfo.isLogined);
                
                int rawBufferLen = 0;
                const void* rawBuffer = xstream_get_raw_buffer(result, &rawBufferLen);
                
                xipc_send_data(client, rawBuffer, rawBufferLen);
                
                xstream_free(result);
            }
            
            break;
        }
        case OSXRDP_SESSMAN_REQUEST_RELEASESESSION: {
            int sessionId = xstream_readInt32(cmd);
            
            osxrdp_sessionmanager_releasesession(sessionId);
            
            break;
        }
        default:
            break;
    }
    
    xstream_free(cmd);
    return 0;
}

int SessionManagerServer::OnClientAuthorize(xipc_t* t, xipc_t* client) {
    (void)t;
#if DEBUG
    return 0;
#else
    // Accept official Team ID, same-team local Developer signing, or ad-hoc
    // xrdp installed under /Applications/osxrdp (see xipc_is_trusted_xrdp_client).
    return xipc_is_trusted_xrdp_client(client, kTrustedClientTeamId, kTrustedClientSigningIdentifier);
#endif
}

int SessionManagerServer::OnClientRejected(xipc_t* t, xipc_t* client) {
    (void)t;

    pid_t peerPid = 0;
    if (xipc_get_peer_pid(client, &peerPid) == 0) {
        dzlog_error("[SessionManagerServer::OnClientRejected] rejected unauthorized client pid=%d (need signed xrdp with id=%s team=%s or ad-hoc under /Applications/osxrdp)",
                    (int)peerPid, kTrustedClientSigningIdentifier, kTrustedClientTeamId);
    }
    else {
        dzlog_error("[SessionManagerServer::OnClientRejected] rejected unauthorized client");
    }

    return 0;
}

// state access helpers
void SessionManagerServer::SetState(State s) {
    pthread_mutex_lock(&_stateLock);
    _state = s;
    pthread_mutex_unlock(&_stateLock);
}

SessionManagerServer::State SessionManagerServer::GetState() {
    pthread_mutex_lock(&_stateLock);
    State s = _state;
    pthread_mutex_unlock(&_stateLock);
    return s;
}

bool SessionManagerServer::IsState(State s) {
    pthread_mutex_lock(&_stateLock);
    bool same = (_state == s);
    pthread_mutex_unlock(&_stateLock);
    return same;
}
