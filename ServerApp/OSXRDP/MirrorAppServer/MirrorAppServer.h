#ifndef MirrorAppServer_hpp
#define MirrorAppServer_hpp

#include "ipc.h"
#include "../ScreenRecorder/ScreenRecorderManager.h"
#include "../Clipboard/ClipboardManager.h"
#include <pthread.h>

struct MirrorAppClientCtx {
    ScreenRecorderManager* ScreenRecorder; // currently only one.
    ClipboardManager* Clipboard;
};

class MirrorAppServer {
public:
    MirrorAppServer();
    ~MirrorAppServer();
    
    void Start();
    void Stop();
    bool IsRunning();
    bool HasConnectedClient();
    bool HasRemoteClipboardFiles();
    int GetRemoteClipboardFileCount();
    void StartRemoteClipboardFileCopy();
    void StartRemoteClipboardFileCopyToDownloads();
    
private:
    // state machine
    enum State {
        State_Idle = 0,
        State_Starting,
        State_Running,
        State_Stopping,
        State_Stopped
    };
    
    // IPC
    xipc_t* _cmdPipe;
    
    xipc_t* _client; // currently, only one client can connect per each account
    
    // synchronization/thread
    pthread_mutex_t _stateLock;
    pthread_mutex_t _clientLock;
    pthread_t _ioThread;
    int _ioThreadStarted;
    State _state;
    
    // internal helpers
    bool CreateCommandPipeServer();
    void DestroyCommandPipeServer();
    
    bool StartIoThread();
    void StopIoThread();
    void SignalIoThreadToStop();
    
    static void* IoThreadEntry(void* arg);
    
    // state access helpers
    void SetState(State s);
    State GetState();
    bool IsState(State s);
    
    // xipc callbacks
    static int OnClientAuthorize(xipc_t* t, xipc_t* client);
    static int OnClientRejected(xipc_t* t, xipc_t* client);
    static int OnClientConnected(xipc_t* t, xipc_t* client);
    static int OnClientDisconnected(xipc_t* t, xipc_t* client);
    static int OnMessageReceived(xipc_t* t, xipc_t* client, void* data, int len);
    
    // misc
    ScreenRecorderManager* CreateScreenRecorder();
};

#endif /* MirrorAppServer_hpp */
