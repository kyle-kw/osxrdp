
#ifndef VirtualMonitor_h
#define VirtualMonitor_h

#include "CGVirtualDisplayPrivate.h"
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <pthread.h>

struct VIRTUALMONITOR_INFO {
    int left;
    int top;
    int width;
    int height;
    int is_retina;
    int is_primary;
    CGVirtualDisplay* virtualDisplay;
};

class VirtualMonitor {
public:
    VirtualMonitor();
    ~VirtualMonitor();
    
    // Create virtual monitor
    bool Create(int width, int height, int left, int top, int index, bool isPrimary = false);
    
    // Destroy all virtual monitors
    void Destroy();
    
    // Disable all monitors except virtual monitor
    // Restored when virtual monitor is destroyed
    bool DisableOtherMonitors();
    
    // Re-enable previously disabled monitors
    void RestoreOtherMonitors();
    
    void StartMonitor();
    
    bool IsRetina(int index) {
        if (index >= _virtualDisplayInfoCnt) return false;
        return _virtualDisplayInfo[index].is_retina == 0 ? false : true;
    }
    
    int GetDisplayId(int index) {
        if (index >= _virtualDisplayInfoCnt) return -1;
        return (int)_virtualDisplayInfo[index].virtualDisplay.displayID;
    }
    
    void HoldDisplaySleepAssertion();
    void ReleaseDisplaySleepAssertion();
    
    static void WakeupDisplay();
    
private:

    struct VIRTUALMONITOR_INFO _virtualDisplayInfo[16];
    int _virtualDisplayInfoCnt;

    bool _init;
    
    uint32_t* _disabledDisplayIds;
    int _disabledDisplayIdsCnt;
    
    pthread_t _watchThread;
    pthread_mutex_t _watchLock;
    pthread_cond_t _watchWake;
    bool _watchRunning;
    IOPMAssertionID _displaySleepAssertion;

    bool IsVirtualDisplay(CGDirectDisplayID displayId);
    bool IsAllVirtualDisplayOnline();
    int GetPrimaryDisplayIndex();
    bool IsRightPrimaryDisplay();
    bool IsRightDisplayLayout();

    int SetResolution(int index);
    bool IsRightResolution(int index);
    int SetPrimaryDisplay();
    int ApplyDisplayLayout();
    
    void WatchThreadPorcInternal();
    
    static void* WatchThreadProc(void* args);
};

#endif /* VirtualMonitor_h */
