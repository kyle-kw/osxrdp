#include "StatusManager.h"

StatusManager::StatusManager()
    : _status(OSXUPStatus::INIT),
    _suppress(false)
{
    
}

StatusManager::~StatusManager() {
    
}

bool StatusManager::CheckInitStatus() {
    return _status == OSXUPStatus::INIT || _status == OSXUPStatus::REQUESTSESSION;
}

bool StatusManager::CheckCanPaint() {
    // Do not paint if suppress is explicitly requested
    if (_suppress == true) {
        return false;
    }
    
    // Paint if lock screen or main agent has started recording
    if (_status == OSXUPStatus::AGENT_RECORD || _status == OSXUPStatus::AGENT_RECORD_LOCKSCREEN) {
        return true;
    }
    
    // Do not paint in other states
    return false;
}

bool StatusManager::CheckNeedTerminate() {
    return _status == OSXUPStatus::REQ_TERMINATE;
}

bool StatusManager::CheckInLockscreen() {
    return _status == OSXUPStatus::AGENT_CONNECTED_LOCKSCREEN;
}

bool StatusManager::CheckReconnection() {
    return _status == OSXUPStatus::AGENT_RECORD_LOCKSCREEN;
}

void StatusManager::SetRequestSession() {
    if (_status == OSXUPStatus::REQ_TERMINATE) {
        return;
    }
    _status = OSXUPStatus::REQUESTSESSION;
}

void StatusManager::SetAgentConnecting(bool lockscreen) {
    if (_status == OSXUPStatus::REQ_TERMINATE) {
        return;
    }
    
    _status = lockscreen ? OSXUPStatus::AGENT_CONNECTING_LOCKSCREEN : OSXUPStatus::AGENT_CONNECTING;
}

void StatusManager::SetAgentConnected(bool lockscreen) {
    if (_status == OSXUPStatus::REQ_TERMINATE) {
        return;
    }
    
    _status = lockscreen ? OSXUPStatus::AGENT_CONNECTED_LOCKSCREEN : OSXUPStatus::AGENT_CONNECTED;
}

void StatusManager::SetAgentRecordStart(bool lockscreen) {
    if (_status == OSXUPStatus::REQ_TERMINATE) {
        return;
    }
    
    _status = lockscreen ? OSXUPStatus::AGENT_RECORD_LOCKSCREEN : OSXUPStatus::AGENT_RECORD;
}

void StatusManager::SetStopping() {
    _status = OSXUPStatus::REQ_TERMINATE;
}

void StatusManager::SetSuppressed(bool suppress) {
    _suppress = suppress;
}
