#include "../pch.h"
#include "../osxup.h"
#include "ConnectionManager.h"
#include "osxrdp/packet.h"
#include "utils.h"

// Session manager server name
static const char* OSXRDP_SESSIONMANAGER_NAME = "/tmp/osxrdpsessionmanager";
static const char* OSXRDP_AGENT_NAME = "/tmp/osxrdp";

static const int OSXRDP_RECONNECT_WAITCNT = 30;

namespace {
inline void AddWaitObject(void* read_objs, int* rcount, int fd) {
    if (read_objs == NULL || rcount == NULL || fd < 0) {
        return;
    }

    ((intptr_t*)read_objs)[*rcount] = (intptr_t)fd;
    (*rcount)++;
}
}

ConnectionManager::ConnectionManager() :
    _inited(false),
    _sessionIpc(NULL),
    _agentIpc(NULL),
    _sessionId(0),
    _mod(NULL)
{}

ConnectionManager::~ConnectionManager() {}

int ConnectionManager::Initialize() {
    assert(_inited == false);
    assert(_agentIpc == NULL);
    assert(_sessionIpc == NULL);
    
    // Always connect to session manager first
    if (_ConnectToSessionManager() == false) {
        // log
        return -1;
    }
    
    _inited = true;
    
    // log
    
    return 0;
}

bool ConnectionManager::Connect(const mod* mod) {
    assert(mod != NULL);
    
    if (mod == NULL) {
        // log
        return false;
    }
    
    if (PaintManager::CheckRecordFormat(mod) == -1) {
        // log
        return false;
    }
    
    size_t usernameLen = strlen(mod->username);
    if (usernameLen == 0 || usernameLen > 260) {
        // log
        return false;
    }
    
    _mod = mod;
    _channelManager.Initialize(mod);
    
    _command.SendSessionRequestMsg(_sessionIpc, mod->username, (int)usernameLen);
    
    return true;
}

void ConnectionManager::Release() {
    if (_inited == false) return;
    
    // close all ipc
    if (_agentIpc != NULL) {
        xipc_loop_once(_agentIpc);
        xipc_destroy(_agentIpc);
        _agentIpc = NULL;
    }
    
    if (_sessionIpc != NULL) {
        xipc_loop_once(_sessionIpc);
        xipc_destroy(_sessionIpc);
        _sessionIpc = NULL;
    }
    
    _paintManager.Release();
    _channelManager.Release();
    
    _inited = false;
}

void ConnectionManager::KeepAlive() {
    // If connected to agent IPC
    if (_agentIpc != NULL) {
        // Process queued messages
        xipc_loop_once(_agentIpc);

        // If connection is lost
        if (_agentIpc->closed == 1) {
            // Destroy
            xipc_destroy(_agentIpc);
            _agentIpc = NULL;
        }
    }
    
    // If connected to session IPC
    if (_sessionIpc != NULL) {
        // Process queued messages
        xipc_loop_once(_sessionIpc);
        
        if (_sessionIpc->closed == 1) {
            // Destroy
            xipc_destroy(_sessionIpc);
            _sessionIpc = NULL;
            
            // If session IPC is disconnected, terminate connection
            _statusManager.SetStopping();
            
            return;
        }
    }
    
    // If agent connection is lost (excluding initial connection)
    if (_agentIpc == NULL && _statusManager.CheckInitStatus() == false) {
        
        _sessionId = -1;
        
        // Painter and cursor manager must be recreated (agent-dependent)
        // However, do not release shared memory until in-flight frame ACKs are done.
        if (_paintManager.TryReleaseForReconnect() == false) {
            return;
        }
        
        // If last attempt was lock screen, reconnect
        if (_statusManager.CheckReconnection() == false) {
            // Otherwise terminate
            _statusManager.SetStopping();
        }
        else {
            // Query session info again to retry session reconnection
            _statusManager.SetRequestSession();
            _command.SendSessionRequestMsg(_sessionIpc, _mod->username, (int)strlen(_mod->username));
        }
    }
}

void ConnectionManager::GetWaitObjects(void* read_objs, int* rcount) {
    if (read_objs == NULL || rcount == NULL) {
        return;
    }

    if (_agentIpc != NULL) {
        AddWaitObject(read_objs, rcount, _agentIpc->fd);
        AddWaitObject(read_objs, rcount, _agentIpc->wakeup_pipe[0]);
    }

    if (_sessionIpc != NULL) {
        AddWaitObject(read_objs, rcount, _sessionIpc->fd);
        AddWaitObject(read_objs, rcount, _sessionIpc->wakeup_pipe[0]);
    }
}

void ConnectionManager::SendMouseInput(int inputType, short x, short y) {
    assert(_agentIpc != NULL);
    
    _command.SendMouseInputMsg(_agentIpc, inputType, x, y);
}

void ConnectionManager::SendKeyboardInput(int inputType, int keycode, int flags) {
    assert(_agentIpc != NULL);

    _command.SendKeyboardInputMsg(_agentIpc, inputType, keycode, flags);
}

bool ConnectionManager::CanPaint() {
    return _statusManager.CheckCanPaint();
}

bool ConnectionManager::NeedTerminate() {
    return _statusManager.CheckNeedTerminate();
}

void ConnectionManager::SetSuppress(bool suppress) {
    _statusManager.SetSuppressed(suppress);
}

void ConnectionManager::Terminate() {
    _statusManager.SetStopping();
}

void ConnectionManager::Paint() {    
    _paintManager.Paint();
}

void ConnectionManager::PaintEnd(int ackFrameId) {
    _paintManager.PaintEnd(ackFrameId);
}

void ConnectionManager::HandleChannelMsg(long param1, long param2, long param3, long param4) {
    // extract channel data
    int channelId = (int)LOWORD(param1);
    int channelFlags = (int)HIWORD(param1);
    int dataLen = (int)param2;
    const char* data = (const char*)param3;
    int totalLen = (int)param4;
    
    // Check if it's a valid (handled) event
    int channel_msg_type = _channelManager.IsValidChannelMsg(channelId, channelFlags, data, dataLen, totalLen);
    if (channel_msg_type == OSXRDP_CHANNEL_INVALID) {
        return;
    }

    if (_agentIpc == NULL) {
        return;
    }
    
    // Only handle clipboard for now (forward to agent)
    if (channel_msg_type == OSXRDP_CHANNEL_CLIPBOARD) {
        _command.SendClipboardMsg(_agentIpc, channelId, channelFlags, data, dataLen, totalLen);
    }
}

bool ConnectionManager::_ConnectToSessionManager() {
    xipc_t* ipc = xipc_ctx_create(_OnReceivedSessionManagerMessage, this);
    if (ipc == NULL) {
        return false;
    }
    
    if (xipc_connect_server(ipc, OSXRDP_SESSIONMANAGER_NAME) != 0) {
        xipc_destroy(ipc);
        
        return false;
    }
    
    // Change state
    _statusManager.SetRequestSession();
    
    _sessionIpc = ipc;
    
    return true;
}

bool ConnectionManager::_ConnectToAgent(int sessionId, bool isLockScreen) {
    assert(sessionId > 0);
    
    printf("Connect to agent %d %d\n", sessionId, isLockScreen);
    
    // Change state
    _statusManager.SetAgentConnecting(isLockScreen);
    
    // Save session id
    _sessionId = sessionId;
    
    // Connect to agent
    xipc_t* ipc = xipc_ctx_create(_OnReceivedAgentManagerMessage, this);
    if (ipc == NULL) {
        // log
        return false;
    }
    
    // Find agent address matching state
    char server_name[512] = {0,};
    if (get_object_name(sessionId, OSXRDP_AGENT_NAME, server_name, sizeof(server_name), isLockScreen) == 0) {
        // log
        xipc_destroy(ipc);
        return false;
    }
    
    // Connect to agent
    // Agent may start late, so retry multiple times (with timeout)
    bool connected = false;
    for (int i = 0; i < OSXRDP_RECONNECT_WAITCNT; i++) {
        if (xipc_connect_server(ipc, server_name) == 0) {
            connected = true;
            break;
        }
        
        // If a terminate request arrived during connection attempts (possible?)
        if (_statusManager.CheckNeedTerminate()) {
            connected = false;
            break;
        }
      
        sleep(1);
    }
    
    if (connected == false) {
        xipc_destroy(ipc);
        
        return false;
    }
    
    // Update connection completed state
    _statusManager.SetAgentConnected(isLockScreen);
    
    // Request screen recording data
    if (_mod->client_info.display_sizes.monitorCount == 0) {
        _command.SendRecordStartMsg(ipc, _mod->width, _mod->height, PaintManager::CheckRecordFormat(_mod), _mod->usevirtualmon, 0, 0);
    }
    else {
        _command.SendRecordStartMsg(ipc, _mod->width, _mod->height, PaintManager::CheckRecordFormat(_mod), _mod->usevirtualmon, _mod->client_info.display_sizes.monitorCount, (struct monitor_info*)_mod->client_info.display_sizes.minfo_wm);
    }
    
    
    // Enable clipboard
    _channelManager.SendClipboardServerInit();
    
    _agentIpc = ipc;

    return true;
}

bool ConnectionManager::_PreparePaint() {
    
    bool inLockscreen = _statusManager.CheckInLockscreen();
    if (_paintManager.Initialize(_mod, PaintManager::CheckRecordFormat(_mod), _sessionId, inLockscreen) == false) {
        // log
        
        return false;
    }
    
    _statusManager.SetAgentRecordStart(inLockscreen);
    
    return true;
}

void ConnectionManager::_HandleSessionMessage(int sessionId, int isLockScreen) {
    if (sessionId <= 0) {
        // log
        _statusManager.SetStopping();
        return;
    }
    
    if (_ConnectToAgent(sessionId, isLockScreen) == false) {
        // log
        _statusManager.SetStopping();
        return;
    }
}

int ConnectionManager::_OnReceivedSessionManagerMessage(xipc_t* t, xipc_t* client, void* data, int len) {
    assert(t != NULL);
    assert(data != NULL);
    assert(len > 0);
    
    if (t == NULL) {
        return -1;
    }
    
    if (data == NULL || len <= 0) {
        return -1;
    }
    
    ConnectionManager* _this = (ConnectionManager*)t->user_data;
    
    xstream_t* stream = xstream_create_for_read(data, len);
    int cmdType = xstream_readInt32(stream);
    
    switch (cmdType) {
        case OSXRDP_SESSMAN_REPLY_SESSION: {
            int sessionId = xstream_readInt32(stream);
            int isLogined = xstream_readInt32(stream);
                        
            _this->_HandleSessionMessage(sessionId, isLogined == 0 ? true : false);
        
            break;
        }
        default:
            break;
    }

    xstream_free(stream);
    
    return 0;
}

int ConnectionManager::_OnReceivedAgentManagerMessage(xipc_t* t, xipc_t* client, void* data, int len) {
    assert(t != NULL);
    assert(data != NULL);
    assert(len > 0);
    
    if (t == NULL) {
        return -1;
    }
    
    if (data == NULL || len <= 0) {
        return -1;
    }
    
    ConnectionManager* _this = (ConnectionManager*)t->user_data;
    
    xstream_t* stream = xstream_create_for_read(data, len);
    int cmdType = xstream_readInt32(stream);
    
    switch (cmdType) {
        case OSXRDP_CMDTYPE_NEEDPAINT: {
            int displayIdx = xstream_readInt32(stream);
            
            _this->_paintManager.PreparePaint(displayIdx);
            
            break;
        }
        case OSXRDP_CMDTYPE_SCREEN: {
            int packetType = xstream_readInt32(stream);
            if (packetType == OSXRDP_PACKETTYPE_REP_SCREEN) {
                int re = xstream_readInt32(stream);
                if (re != 1 || _this->_PreparePaint() == false) {
                    // log
                    _this->_statusManager.SetStopping();
                }
            }
            break;
        }
        case OSXRDP_CMDTYPE_CLIPBOARD: {
            int packetType = xstream_readInt32(stream);
            if (packetType == OSXRDP_PACKETTYPE_REP_SETCLIENTCLIP) {
                int channelFlags = xstream_readInt32(stream);
                int totalLen = xstream_readInt32(stream);
                int dataLen = xstream_readInt32(stream);
                const void* rawData = xstream_readData(stream, dataLen);

                if (rawData != NULL) {
                    _this->_channelManager.SendClipboardChannelData(rawData,
                                                                    dataLen,
                                                                    totalLen,
                                                                    channelFlags);
                }
            }
            break;
        }
        case OSXRDP_CMDTYPE_MSGFROMAGENT: {
            int packetType = xstream_readInt32(stream);
            if (packetType == OSXRDP_PACKETTYPE_TERMINATE) {
                // log
                _this->_statusManager.SetStopping();
            }
            break;
        }
        default:
            break;
    }
    
    xstream_free(stream);
    return 0;
}
