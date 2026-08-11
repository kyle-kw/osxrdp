#include "../pch.h"
#include "../osxup.h"
#include "ConnectionManager.h"
#include "osxrdp/packet.h"
#include "utils.h"
#include "UserIdentityResolver.h"
#include "osxrdp/stream_policy.h"
#include <time.h>
#include <unistd.h>
#include <pwd.h>

// Session manager server name
static const char* kTrustedTeamId = "33X7M69J4B";
static const char* kSessionManagerIdentifier = "com.byungho.osxrdp.sessionmanager";
static const char* kSessionManagerAdhocPath = "/Applications/osxrdp/OSXRDP.app/Contents/MacOS/osxrdp_sessionmanager";
static const char* kAgentIdentifier = "com.byungho.osxrdp.mainapp";
static const char* kAgentAdhocPath = "/Applications/osxrdp/OSXRDP.app/Contents/MacOS/OSXRDP";

static const int OSXRDP_RECONNECT_WAITCNT = 30;
// If REP_SCREENRESIZE never arrives, complete the xrdp handshake and free the flag.
static const long long kResizeTimeoutMs = 5000;

namespace {
inline void AddWaitObject(void* read_objs, int* rcount, int fd) {
    if (read_objs == NULL || rcount == NULL || fd < 0) {
        return;
    }

    ((intptr_t*)read_objs)[*rcount] = (intptr_t)fd;
    (*rcount)++;
}

inline long long NowMs() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

const char* ScreenErrorMessage(int error) {
    switch (error) {
        case OSXRDP_SCREEN_ERROR_H264_UNSUPPORTED:
            return "Screen recording failed: the client did not negotiate RDP GFX H.264.";
        case OSXRDP_SCREEN_ERROR_MULTIMONITOR_UNSUPPORTED:
            return "Screen recording failed: this streaming mode does not support multiple monitors.";
        case OSXRDP_SCREEN_ERROR_VIDEOTOOLBOX_INITIALIZATION:
            return "Screen recording failed: VideoToolbox could not initialize.";
        case OSXRDP_SCREEN_ERROR_ENCODER_RUNTIME:
            return "Screen recording failed: VideoToolbox stopped encoding.";
        case OSXRDP_SCREEN_ERROR_UNKNOWN_POLICY:
            return "Screen recording failed: the streaming policy version is unsupported.";
        default:
            return "Screen recording failed: the agent rejected the request.";
    }
}
} // namespace

ConnectionManager::ConnectionManager() :
    _inited(false),
    _sessionIpc(NULL),
    _agentIpc(NULL),
    _sessionId(0),
    _targetUid((uid_t)-1),
    _mod(NULL),
    _recordFormat(-1),
    _encoderFallback(false),
    _paintStarted(false),
    _lastFrameActivityMs(0),
    _pendingResizeWidth(0),
    _pendingResizeHeight(0),
    _pendingResizeMonitorCount(0),
    _resizeInProgress(false),
    _resizeStartedMs(0)
{
    osxrdp_stream_policy_resolve(OSXRDP_STREAM_QUALITY_DEFAULT, &_streamPolicy);
}

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
    
    int negotiatedFormat = PaintManager::CheckRecordFormat(mod);
    if (negotiatedFormat == -1) {
        // log
        return false;
    }
    
    size_t usernameLen = strlen(mod->username);
    if (usernameLen == 0 || usernameLen > 260) {
        // log
        return false;
    }

    struct passwd passwordEntry;
    struct passwd* passwordResult = NULL;
    char passwordBuffer[4096];
    if (getpwnam_r(mod->username, &passwordEntry, passwordBuffer, sizeof(passwordBuffer), &passwordResult) != 0 ||
        passwordResult == NULL) {
        return false;
    }
    _targetUid = passwordEntry.pw_uid;

    int preset = osxup_get_stream_quality_preset(mod->username);
    osxrdp_stream_policy_resolve(preset, &_streamPolicy);
    _recordFormat = negotiatedFormat;
    _encoderFallback = false;
    _paintStarted = false;
    if (_streamPolicy.usesAgentH264) {
        bool hasH264 = negotiatedFormat == OSXRDP_RECORDFORMAT_NV12_PACKED ||
                       negotiatedFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED;
        if (!hasH264) {
            mod->server_msg((struct mod*)mod,
                "The selected streaming quality requires an RDP GFX H.264 client.", 0);
            return false;
        }
        if (mod->client_info.display_sizes.monitorCount > 1) {
            mod->server_msg((struct mod*)mod,
                "Hotspot and Extreme Saver modes do not support multiple monitors.", 0);
            mod->server_msg((struct mod*)mod,
                "Disable multiple monitors or select High Quality before reconnecting.", 0);
            return false;
        }
        _recordFormat = OSXRDP_RECORDFORMAT_H264_ANNEXB;
    }
    
    _mod = mod;
    _channelManager.Initialize(mod);
    
    _command.SendSessionRequestMsg(_sessionIpc, mod->username, (int)usernameLen);
    
    return true;
}

void ConnectionManager::_ClearResizeState() {
    _resizeInProgress = false;
    _resizeStartedMs = 0;
    _pendingResizeWidth = 0;
    _pendingResizeHeight = 0;
    _pendingResizeMonitorCount = 0;
}

void ConnectionManager::_AbortResizeInProgress() {
    if (_resizeInProgress == false) {
        return;
    }
    // Complete the async handshake so xrdp is not left waiting for done.
    if (_mod != NULL && _mod->server_monitor_resize_done != NULL) {
        _mod->server_monitor_resize_done((struct mod*)_mod);
    }
    _ClearResizeState();
}

void ConnectionManager::_CheckResizeTimeout() {
    if (_resizeInProgress == false || _resizeStartedMs == 0) {
        return;
    }
    if (NowMs() - _resizeStartedMs < kResizeTimeoutMs) {
        return;
    }
    if (_mod != NULL) {
        _mod->server_msg((struct mod*)_mod,
            "Screen resize timed out waiting for agent; keeping previous resolution.", 0);
    }
    _AbortResizeInProgress();
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

    // Drop any in-flight resize so a later reconnect can accept a new one
    _AbortResizeInProgress();
    
    _paintManager.Release();
    _paintStarted = false;
    _channelManager.Release();
    
    _inited = false;
}

void ConnectionManager::KeepAlive() {
    // Fail open if agent never replies to an in-flight resize
    _CheckResizeTimeout();

    // If connected to agent IPC
    if (_agentIpc != NULL) {
        // Process queued messages
        xipc_loop_once(_agentIpc);

        // If connection is lost
        if (xipc_is_closed(_agentIpc)) {
            // Destroy
            xipc_destroy(_agentIpc);
            _agentIpc = NULL;
            // REP may never arrive — complete handshake and unblock future resizes
            _AbortResizeInProgress();
        }
    }
    
    // If connected to session IPC
    if (_sessionIpc != NULL) {
        // Process queued messages
        xipc_loop_once(_sessionIpc);
        
        if (xipc_is_closed(_sessionIpc)) {
            // Destroy
            xipc_destroy(_sessionIpc);
            _sessionIpc = NULL;
            
            // If session IPC is disconnected, terminate connection
            _AbortResizeInProgress();
            _statusManager.SetStopping();
            
            return;
        }
    }
    
    // If agent connection is lost (excluding initial connection)
    if (_agentIpc == NULL && _statusManager.CheckInitStatus() == false) {
        
        _sessionId = -1;
        // Ensure flag is clear even if agent was already NULL without going
        // through the closed==1 path above (e.g. failed connect after request).
        // Idempotent if already aborted above.
        _AbortResizeInProgress();
        
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
    _AbortResizeInProgress();
    _statusManager.SetStopping();
}

void ConnectionManager::_RecordFrameActivity() {
    _lastFrameActivityMs = NowMs();
}

bool ConnectionManager::SendResolutionChange(int width, int height, int recordFormat, int useVirtualmon, int monitorCount, const struct monitor_info* monitorInfo) {
    // Reject concurrent resize while one is already in flight
    if (_resizeInProgress || _agentIpc == NULL) {
        return false;
    }
    if (_mod == NULL || _mod->client_monitor_resize == NULL || _mod->server_monitor_resize_done == NULL) {
        if (_mod != NULL && _mod->server_msg != NULL) {
            _mod->server_msg((struct mod*)_mod, "Screen resize is unavailable: required xrdp callbacks are missing.", 0);
        }
        _ClearResizeState();
        return false;
    }

    // Even-align once so pending layout, wire message, and agent SHM all match.
    width &= ~0x1;
    height &= ~0x1;
    if (width <= 0 || height <= 0) {
        return false;
    }

    // Store pending resize for async completion in REP_SCREENRESIZE handler
    _pendingResizeWidth = width;
    _pendingResizeHeight = height;
    if (monitorInfo != NULL && monitorCount > 0) {
        int cnt = monitorCount > 16 ? 16 : monitorCount;
        _pendingResizeMonitorCount = cnt;
        memcpy(_pendingResizeMonitors, monitorInfo, sizeof(struct monitor_info) * cnt);
    } else {
        // Single-monitor / non-multimon path: synthesize one primary monitor
        // so xrdp client_monitor_resize still receives a layout on success.
        _pendingResizeMonitorCount = 1;
        memset(&_pendingResizeMonitors[0], 0, sizeof(_pendingResizeMonitors[0]));
        _pendingResizeMonitors[0].left = 0;
        _pendingResizeMonitors[0].top = 0;
        _pendingResizeMonitors[0].right = width;
        _pendingResizeMonitors[0].bottom = height;
        _pendingResizeMonitors[0].is_primary = 1;
    }

    _resizeInProgress = true;
    _resizeStartedMs = NowMs();
    (void)recordFormat;
    if (_command.SendScreenResizeMsg(_agentIpc, width, height, _streamPolicy.framerate,
                                     _recordFormat, useVirtualmon,
                                     _pendingResizeMonitorCount, _pendingResizeMonitors,
                                     OSXRDP_STREAM_POLICY_VERSION, _streamPolicy.preset) == false) {
        _ClearResizeState();
        return false;
    }
    return true;
}

int ConnectionManager::GetAdaptiveTimeout() {
    // While a resize is in flight, wake often enough to honor kResizeTimeoutMs promptly.
    if (_resizeInProgress) {
        return 50;
    }
    if (_lastFrameActivityMs == 0) {
        return 100;
    }
    long long now = NowMs();
    if (now - _lastFrameActivityMs < 500) {
        return 10; // Active streaming: short timeout for fast backlog drain
    }
    return 100; // Idle: long timeout to avoid busy-wake
}

void ConnectionManager::Paint() {    
    if (_paintManager.Paint() == false) {
        _statusManager.SetStopping();
    }
}

void ConnectionManager::PaintEnd(int ackFrameId) {
    _paintManager.PaintEnd(ackFrameId);
    _RecordFrameActivity();
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
    
    char socketPath[128] = {0};
    if (osxrdp_get_sessionmanager_socket_path(socketPath, sizeof(socketPath)) == 0 ||
        xipc_connect_server_verified(ipc, socketPath, 0, 0) != 0 ||
        xipc_is_trusted_peer(ipc, kTrustedTeamId, kSessionManagerIdentifier,
                             kSessionManagerAdhocPath) != 0) {
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
    uid_t agentUid = isLockScreen ? 0 : _targetUid;
    if (agentUid == (uid_t)-1 ||
        osxrdp_get_agent_socket_path(agentUid, sessionId, server_name, sizeof(server_name), isLockScreen) == 0) {
        // log
        xipc_destroy(ipc);
        return false;
    }
    
    // Connect to agent
    // Agent may start late, so retry multiple times (with timeout)
    bool connected = false;
    for (int i = 0; i < OSXRDP_RECONNECT_WAITCNT; i++) {
        if (xipc_connect_server_verified(ipc, server_name, agentUid, (gid_t)-1) == 0) {
            if (xipc_is_trusted_peer(ipc, kTrustedTeamId, kAgentIdentifier, kAgentAdhocPath) == 0) {
                connected = true;
                break;
            }
            xipc_destroy(ipc);
            return false;
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
        _command.SendRecordStartMsg(ipc, _mod->width, _mod->height, _streamPolicy.framerate,
                                    _recordFormat, _mod->usevirtualmon, 0, 0,
                                    OSXRDP_STREAM_POLICY_VERSION, _streamPolicy.preset);
    }
    else {
        _command.SendRecordStartMsg(ipc, _mod->width, _mod->height, _streamPolicy.framerate,
                                    _recordFormat, _mod->usevirtualmon,
                                    _mod->client_info.display_sizes.monitorCount,
                                    (struct monitor_info*)_mod->client_info.display_sizes.minfo_wm,
                                    OSXRDP_STREAM_POLICY_VERSION, _streamPolicy.preset);
    }
    
    
    // Enable clipboard
    _channelManager.SendClipboardServerInit();
    
    _agentIpc = ipc;

    return true;
}

bool ConnectionManager::_PreparePaint() {
    
    bool inLockscreen = _statusManager.CheckInLockscreen();
    if (_paintManager.Initialize(_mod, _recordFormat, _sessionId, inLockscreen) == false) {
        // log
        
        return false;
    }
    
    _statusManager.SetAgentRecordStart(inLockscreen);
    _paintStarted = true;
    
    return true;
}

bool ConnectionManager::_RequestOpenH264Fallback(xipc_t* ipc, int errorCode) {
    if (ipc == NULL || _mod == NULL || !_streamPolicy.usesAgentH264 || _encoderFallback ||
        (errorCode != OSXRDP_SCREEN_ERROR_VIDEOTOOLBOX_INITIALIZATION &&
         errorCode != OSXRDP_SCREEN_ERROR_ENCODER_RUNTIME)) {
        return false;
    }
    _encoderFallback = true;
    _recordFormat = OSXRDP_RECORDFORMAT_NV12_PACKED;
    _mod->server_msg((struct mod*)_mod,
        "VideoToolbox is unavailable. Retrying with OpenH264 fallback; bitrate is not guaranteed.", 0);
    int monitorCount = _mod->client_info.display_sizes.monitorCount;
    struct monitor_info* monitorInfo =
        (struct monitor_info*)_mod->client_info.display_sizes.minfo_wm;
    return _command.SendRecordStartMsg(ipc, _mod->width, _mod->height,
        _streamPolicy.framerate, _recordFormat, _mod->usevirtualmon,
        monitorCount, monitorCount > 0 ? monitorInfo : NULL,
        OSXRDP_STREAM_POLICY_VERSION, _streamPolicy.preset,
        OSXRDP_PACKETTYPE_REQ_SCREENRECONFIGURE);
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
            _this->_RecordFrameActivity();
            
            break;
        }
        case OSXRDP_CMDTYPE_SCREEN: {
            int packetType = xstream_readInt32(stream);
            if (packetType == OSXRDP_PACKETTYPE_REP_SCREEN) {
                int re = xstream_readInt32(stream);
                int error = xstream_getRemaining(stream) >= (int)sizeof(int)
                    ? xstream_readInt32(stream) : OSXRDP_SCREEN_ERROR_INVALID_REQUEST;
                if (re != 1 && _this->_RequestOpenH264Fallback(client, error)) {
                    break;
                }
                if (re != 1 || _this->_PreparePaint() == false) {
                    if (_this->_mod != NULL && _this->_mod->server_msg != NULL) {
                        _this->_mod->server_msg((struct mod*)_this->_mod,
                            ScreenErrorMessage(error), 0);
                    }
                    // log
                    _this->_statusManager.SetStopping();
                }
            }
            else if (packetType == OSXRDP_PACKETTYPE_REP_SCREENRECONFIGURE) {
                int re = xstream_readInt32(stream);
                int error = xstream_getRemaining(stream) >= (int)sizeof(int)
                    ? xstream_readInt32(stream) : OSXRDP_SCREEN_ERROR_INVALID_REQUEST;
                if (re != 1 && _this->_RequestOpenH264Fallback(client, error)) {
                    break;
                }
                bool ready = false;
                if (re == 1) {
                    ready = _this->_paintStarted
                        ? _this->_paintManager.ReinitializeForResize(_this->_recordFormat)
                        : _this->_PreparePaint();
                }
                if (!ready) {
                    if (_this->_mod != NULL && _this->_mod->server_msg != NULL) {
                        _this->_mod->server_msg((struct mod*)_this->_mod,
                            ScreenErrorMessage(error), 0);
                    }
                    _this->_statusManager.SetStopping();
                }
            }
            else if (packetType == OSXRDP_PACKETTYPE_REP_SCREENRESIZE) {
                int re = xstream_readInt32(stream);
                int newWidth = xstream_readInt32(stream);
                int newHeight = xstream_readInt32(stream);
                int error = xstream_getRemaining(stream) >= (int)sizeof(int)
                    ? xstream_readInt32(stream) : OSXRDP_SCREEN_ERROR_INVALID_REQUEST;

                if (re == 1) {
                    // Update mod dimensions
                    ((struct mod*)_this->_mod)->width = newWidth;
                    ((struct mod*)_this->_mod)->height = newHeight;

                    // Re-initialize PaintManager at new resolution (re-opens SHM)
                    if (_this->_paintManager.ReinitializeForResize() == false) {
                        _this->_mod->server_msg((struct mod*)_this->_mod, "Screen resize failed: could not reinitialize paint manager.", 0);
                        _this->_statusManager.SetStopping();
                    }
                }
                else {
                    _this->_mod->server_msg((struct mod*)_this->_mod, ScreenErrorMessage(error), 0);
                }

                // Complete the async resize handshake with xrdp
                if (_this->_resizeInProgress) {
                    if (_this->_mod == NULL ||
                        _this->_mod->client_monitor_resize == NULL ||
                        _this->_mod->server_monitor_resize_done == NULL) {
                        if (_this->_mod != NULL && _this->_mod->server_msg != NULL) {
                            _this->_mod->server_msg((struct mod*)_this->_mod,
                                "Screen resize failed: required xrdp callbacks are missing.", 0);
                        }
                        _this->_ClearResizeState();
                        break;
                    }
                    if (re == 1) {
                        // Prefer agent-reported even-aligned size for the client layout.
                        int layoutW = (newWidth > 0) ? newWidth : _this->_pendingResizeWidth;
                        int layoutH = (newHeight > 0) ? newHeight : _this->_pendingResizeHeight;
                        layoutW &= ~0x1;
                        layoutH &= ~0x1;

                        int monCount = _this->_pendingResizeMonitorCount;
                        if (monCount <= 0) {
                            monCount = 1;
                            memset(&_this->_pendingResizeMonitors[0], 0, sizeof(_this->_pendingResizeMonitors[0]));
                            _this->_pendingResizeMonitors[0].left = 0;
                            _this->_pendingResizeMonitors[0].top = 0;
                            _this->_pendingResizeMonitors[0].is_primary = 1;
                        }
                        // Keep a single primary full-session monitor consistent with layout size.
                        if (monCount == 1 &&
                            _this->_pendingResizeMonitors[0].left == 0 &&
                            _this->_pendingResizeMonitors[0].top == 0) {
                            _this->_pendingResizeMonitors[0].right = layoutW;
                            _this->_pendingResizeMonitors[0].bottom = layoutH;
                        }

                        _this->_mod->client_monitor_resize((struct mod*)_this->_mod,
                            layoutW, layoutH,
                            monCount, _this->_pendingResizeMonitors);
                    }
                    _this->_mod->server_monitor_resize_done((struct mod*)_this->_mod);
                    _this->_ClearResizeState();
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
