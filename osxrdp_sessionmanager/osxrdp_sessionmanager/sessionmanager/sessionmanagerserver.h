#ifndef SessionManagerServer_hpp
#define SessionManagerServer_hpp

#include "ipc.h"
#include <pthread.h>
#include <stdint.h>

struct SessionManagerServerCtx {
    int unused;
};

class SessionManagerServer {
public:
    SessionManagerServer();
    ~SessionManagerServer();
    
    bool Start();
    void Stop();
    bool IsRunning();
    
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
    
    // synchronization/thread
    pthread_mutex_t _stateLock;
    pthread_t _ioThread;
    int _ioThreadStarted;
    State _state;
    int _pendingLoginWindowSessionId;
    uint64_t _pendingLoginWindowCreatedMs;
    
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
    static int OnMessageReceived(xipc_t* t, xipc_t* client, void* data, int len);
    
};

#endif /* SessionManagerServer_hpp */
