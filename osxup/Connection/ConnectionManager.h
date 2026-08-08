
#ifndef ConnectionManager_h
#define ConnectionManager_h

#include "../Paint/PaintManager.h"
#include "../Status/StatusManager.h"
#include "../Channel/ChannelManager.h"
#include "../Command/Command.h"

#include <pthread.h>
#include <sys/types.h>

struct mod;

class ConnectionManager {
public:
    ConnectionManager();
    ~ConnectionManager();
    
    int Initialize();
    void Release();
    
    // Perform initial connection
    bool Connect(const struct mod* mod);
    
    // IPC message pump and connection status check
    void KeepAlive();
    void GetWaitObjects(void* read_objs, int* rcount);
    
    // Forward mouse input
    void SendMouseInput(int inputType, short x, short y);
    
    // Forward keyboard input
    void SendKeyboardInput(int inputType, int keycode, int flags);
    
    // Status queries
    bool CanPaint();
    bool NeedTerminate();
    void SetSuppress(bool suppress);
    
    void Terminate();
    
    // Forward resolution change to agent (dynamic resize).
    // Returns false if rejected (already in progress / invalid / send failed).
    // On false, caller must NOT leave xrdp waiting for server_monitor_resize_done.
    // Threading: SendResolutionChange (xrdp callback) and REP_SCREENRESIZE handling
    // (via KeepAlive → xipc_loop_once) both run on the xrdp event thread; no lock.
    bool SendResolutionChange(int width, int height, int recordFormat, int useVirtualmon, int monitorCount, const struct monitor_info* monitorInfo);
    
    // Adaptive select timeout based on recent frame activity
    int GetAdaptiveTimeout();
    
    // Screen painting
    void Paint();
    void PaintEnd(int ackFrameId);
    
    // handle channel msg (clipboard, etc)
    void HandleChannelMsg(long param1, long param2, long param3, long param4);
    
private:
    bool _inited;
    StatusManager _statusManager;
    Command _command;
    PaintManager _paintManager;
    ChannelManager _channelManager;
    
    xipc_t* _sessionIpc;
    xipc_t* _agentIpc;
    int _sessionId;
    uid_t _targetUid;
    const mod* _mod;
    
    // Adaptive timeout: last frame activity timestamp (ms, monotonic)
    long long _lastFrameActivityMs;
    
    // Pending async monitor resize request
    int _pendingResizeWidth;
    int _pendingResizeHeight;
    int _pendingResizeMonitorCount;
    struct monitor_info _pendingResizeMonitors[16];
    bool _resizeInProgress;
    // Monotonic ms when _resizeInProgress was set; 0 if idle.
    long long _resizeStartedMs;
    
    void _RecordFrameActivity();
    // Clear pending resize fields only (no xrdp callback). Use when in_progress was never set.
    void _ClearResizeState();
    // If a resize handshake is open, complete it with server_monitor_resize_done then clear.
    // Required on agent drop so xrdp does not hang and later resizes are not blocked.
    void _AbortResizeInProgress();
    // Fail open if agent never replies to REQ_SCREENRESIZE (see kResizeTimeoutMs).
    void _CheckResizeTimeout();
    
    bool _ConnectToSessionManager();
    bool _ConnectToAgent(int sessionId, bool isLockScreen);
    bool _PreparePaint();
        
    void _HandleSessionMessage(int sessionId, int isLockScreen);
    
    // Handle session manager received messages
    static int _OnReceivedSessionManagerMessage(xipc_t* t, xipc_t* client, void* data, int len);
    
    // Handle agent received messages
    static int _OnReceivedAgentManagerMessage(xipc_t* t, xipc_t* client, void* data, int len);
};

#endif /* ConnectionManager_h */
