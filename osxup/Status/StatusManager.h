
#ifndef StatusManager_h
#define StatusManager_h

enum class OSXUPStatus {
    INIT,
    REQUESTSESSION,
    AGENT_CONNECTING_LOCKSCREEN,
    AGENT_CONNECTED_LOCKSCREEN,
    AGENT_RECORD_LOCKSCREEN,
    AGENT_CONNECTING,
    AGENT_CONNECTED,
    AGENT_RECORD,
    REQ_TERMINATE,
};

class StatusManager {
public:
    StatusManager();
    ~StatusManager();
    
    bool CheckInitStatus();
    
    // Check if painting is possible
    bool CheckCanPaint();
    
    // Check if connection should be terminated
    bool CheckNeedTerminate();
    
    // Check if in lock screen state
    bool CheckInLockscreen();
    
    // Check if lock screen ended and reconnection should be attempted
    bool CheckReconnection();
    
    // Set session request state
    void SetRequestSession();
    
    // Set agent connecting state
    void SetAgentConnecting(bool lockscreen);
    
    // Set agent connected state
    void SetAgentConnected(bool lockscreen);
    
    // Set agent recording started state
    void SetAgentRecordStart(bool lockscreen);
    
    // Set stopping state
    void SetStopping();
    
    // Set suppress state
    void SetSuppressed(bool suppress);
    
private:
    OSXUPStatus _status;
    bool _suppress;
};

#endif /* StatusManager_h */
