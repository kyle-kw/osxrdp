
#ifndef ConnectionManager_h
#define ConnectionManager_h

#include "../Paint/PaintManager.h"
#include "../Status/StatusManager.h"
#include "../Channel/ChannelManager.h"
#include "../Command/Command.h"

#include <pthread.h>

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
    const mod* _mod;
    
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
