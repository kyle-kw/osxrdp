#include "VirtualMonitor.h"
#include "DisplayUtils.h"

#include <IOKit/pwr_mgt/IOPMLib.h>
#include <unistd.h>

static const int kDisplayReconfigSettleUsec = 500 * 1000;

VirtualMonitor::VirtualMonitor() :
    _virtualDisplayInfoCnt(0),
    _init(false),
    _disabledDisplayIds(NULL),
    _disabledDisplayIdsCnt(0),
    _watchRunning(false),
    _displaySleepAssertion(kIOPMNullAssertionID)
{
    pthread_mutex_init(&_watchLock, 0);
    pthread_cond_init(&_watchWake, 0);
}

VirtualMonitor::~VirtualMonitor() {
    Destroy();
    
    pthread_cond_destroy(&_watchWake);
    pthread_mutex_destroy(&_watchLock);
}

bool VirtualMonitor::Create(int width, int height, int left, int top, int index, bool isPrimary) {

    if (_virtualDisplayInfoCnt >= 16) return false;

    HoldDisplaySleepAssertion();
    WakeupDisplay();
    
    // Create virtual display
    CGVirtualDisplayDescriptor* desc = [[CGVirtualDisplayDescriptor alloc] init];
    if (desc == nil) return false;
    
    // Virtual display base properties
    desc.queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    desc.name = @"OSXRDP Virtual Display";
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    desc.sizeInMillimeters = CGSizeMake(width * 25.4 / 96,
                                        height * 25.4 / 96);
    
    desc.productID = 0x5969 + index;
    desc.vendorID = 0x1207;
    desc.serialNum = 0x0007 + index;
    
    CGVirtualDisplayMode* mode = [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:60];
    if (mode == nil) return false;
    
    CGVirtualDisplayMode* retinaMode = [[CGVirtualDisplayMode alloc] initWithWidth:width / 2 height:height / 2 refreshRate:60];
    if (retinaMode == nil) return false;
    
    CGVirtualDisplaySettings* settings = [[CGVirtualDisplaySettings alloc] init];
    if (settings == nil) return false;
    
    // Enable HiDPI mode for high resolutions (hack?)
    if (width > 2300 && height > 1500) {
        settings.hiDPI = 1;
    }
    else {
        settings.hiDPI = 0;
    }
    
    // Without filling the configuration like this, macOS may recognize it as something other than a monitor and show a dialog (AirPlay receiver?)
    // So put default modes like a real monitor, and add the xrdp resolution last.
    settings.modes = @[
        [[CGVirtualDisplayMode alloc] initWithWidth:3840 height:2160 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:2560 height:1440 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1920 height:1080 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1600 height:900 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1366 height:768 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1280 height:720 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:2560 height:1600 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1920 height:1200 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1680 height:1050 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1440 height:900 refreshRate:60],
        [[CGVirtualDisplayMode alloc] initWithWidth:1280 height:800 refreshRate:60],
        mode,
        retinaMode
    ];
    
    CGVirtualDisplay* virtualDisplay = [[CGVirtualDisplay alloc] initWithDescriptor:desc];
    if (virtualDisplay == nil) return false;
    
    // Apply virtual display settings
    [virtualDisplay applySettings:settings];
    
    WakeupDisplay();
    
    _virtualDisplayInfo[_virtualDisplayInfoCnt].left = left;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].top = top;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].width = width;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].height = height;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].is_retina = settings.hiDPI > 0 ? true : false;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].is_primary = isPrimary ? true : false;
    _virtualDisplayInfo[_virtualDisplayInfoCnt].virtualDisplay = virtualDisplay;

    _virtualDisplayInfoCnt++;
    
    DisplayUtils::WaitDisplayOnlineState(virtualDisplay.displayID, true, 5000);

    ApplyDisplayLayout();

    return true;
}

void VirtualMonitor::Destroy() {
    // Stop virtual monitor watch thread
    if (_watchRunning == true) {
        pthread_mutex_lock(&_watchLock);
        _watchRunning = false;
        pthread_cond_signal(&_watchWake);
        pthread_mutex_unlock(&_watchLock);
        pthread_join(_watchThread, NULL); // Wait until fully stopped
    }

    if (_disabledDisplayIdsCnt > 0) {
        WakeupDisplay();
        usleep(kDisplayReconfigSettleUsec);
    }

    // Rollback disabled displays (must do first, otherwise windowserver may crash as described above)
    RestoreOtherMonitors();

    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        // Setting to nil destroys it automatically (not immediately)
        _virtualDisplayInfo[i].virtualDisplay = nil;
    }

    _virtualDisplayInfoCnt = 0;
    memset(&_virtualDisplayInfo, 0x00, sizeof(_virtualDisplayInfo));

    _init = false;
    ReleaseDisplaySleepAssertion();
}

void VirtualMonitor::RestoreOtherMonitors() {
    if (_disabledDisplayIdsCnt == 0 || _disabledDisplayIds == NULL) {
        return;
    }
    
    DisplayUtils::ApplyDisplayEnabled(_disabledDisplayIds, _disabledDisplayIdsCnt, true);
    
    free(_disabledDisplayIds);
    
    _disabledDisplayIds = NULL;
    _disabledDisplayIdsCnt = 0;
}

void VirtualMonitor::StartMonitor() {
    HoldDisplaySleepAssertion();
    WakeupDisplay();

    if (_watchRunning == false) {
        _watchRunning = true;
        pthread_create(&_watchThread , NULL, WatchThreadProc, this);
    }
}

void VirtualMonitor::WakeupDisplay() {
    IOPMAssertionID assertionID = kIOPMNullAssertionID;
    IOPMAssertionDeclareUserActivity(CFSTR("OSXRDP: wake display"), kIOPMUserActiveLocal, &assertionID);
    if (assertionID != kIOPMNullAssertionID) {
        IOPMAssertionRelease(assertionID);
        assertionID = kIOPMNullAssertionID;
    }
}

void VirtualMonitor::HoldDisplaySleepAssertion() {
    if (_displaySleepAssertion != kIOPMNullAssertionID) {
        return;
    }

    IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                kIOPMAssertionLevelOn,
                                CFSTR("OSXRDP virtual monitor session"),
                                &_displaySleepAssertion);
}

void VirtualMonitor::ReleaseDisplaySleepAssertion() {
    if (_displaySleepAssertion == kIOPMNullAssertionID) {
        return;
    }

    IOPMAssertionRelease(_displaySleepAssertion);
    _displaySleepAssertion = kIOPMNullAssertionID;
}

// todo: Duplicate logic exists in DisplayUtils::ApplyDisplayEnabled
bool VirtualMonitor::DisableOtherMonitors() {
    NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors begin virtualDisplayCnt=%d disabledCnt=%d]", _virtualDisplayInfoCnt, _disabledDisplayIdsCnt);
    
    // Ignore if no virtual display
    if (_virtualDisplayInfoCnt <= 0) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=noVirtualDisplay]");
        return false;
    }
    
    // Get display count
    uint32_t displayCnt = 0;
    CGError displayListErr = CGGetOnlineDisplayList(0, NULL, &displayCnt);
    NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors onlineCnt=%u err=%d]", displayCnt, displayListErr);
    
    if (displayListErr != kCGErrorSuccess || displayCnt == 0) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=noDisplay err=%d cnt=%u]", displayListErr, displayCnt);
        return false;
    }
    
    // Get display IDs
    CGDirectDisplayID* displayIds = (CGDirectDisplayID*)malloc(sizeof(CGDirectDisplayID) * displayCnt);
    if (displayIds == NULL) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=mallocDisplayIds cnt=%u]", displayCnt);
        return false;
    }
    
    displayListErr = CGGetOnlineDisplayList(displayCnt, displayIds, NULL);
    if (displayListErr != kCGErrorSuccess) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=getDisplayList err=%d cnt=%u]", displayListErr, displayCnt);
        free(displayIds);
        
        return false;
    }

    bool hasPhysicalOnlineDisplay = false;
    for (uint32_t i = 0; i < displayCnt; i++) {
        if (IsVirtualDisplay(displayIds[i]) == false) {
            hasPhysicalOnlineDisplay = true;
            break;
        }
    }

    if (hasPhysicalOnlineDisplay == false) {
        free(displayIds);
        return true;
    }
    
    uint32_t* newDisabledDisplayIds = (uint32_t*)realloc(_disabledDisplayIds, sizeof(uint32_t) * (_disabledDisplayIdsCnt + displayCnt));
    if (newDisabledDisplayIds == NULL) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=realloc oldCnt=%d addCnt=%u]", _disabledDisplayIdsCnt, displayCnt);
        free(displayIds);
        return false;
    }
    
    _disabledDisplayIds = newDisabledDisplayIds;
    
    CGDisplayConfigRef cfg = NULL;
    CGError beginErr = CGBeginDisplayConfiguration(&cfg);
    if (beginErr != kCGErrorSuccess || cfg == NULL) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=beginConfiguration err=%d cfg=%p]", beginErr, cfg);
        free(displayIds);
        
        return false;
    }
    
    int newDisabledDisplayIdsCnt = _disabledDisplayIdsCnt;
    
    for (uint32_t i = 0; i < displayCnt; i++) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors check id=%u index=%u]", displayIds[i], i);
        
        if (IsVirtualDisplay(displayIds[i])) {
            NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors skip virtual id=%u]", displayIds[i]);
            continue;
        }
        
        // Configure physical display to be disabled
        CGError configureErr = CGSConfigureDisplayEnabled(cfg, displayIds[i], false);
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors configure id=%u enabled=0 err=%d]", displayIds[i], configureErr);
        
        bool exists = false;
        for (int j = 0; j < _disabledDisplayIdsCnt; j++) {
            if (_disabledDisplayIds[j] == displayIds[i]) {
                exists = true;
                break;
            }
        }
        
        if (exists == false) {
            // Save ID for later restoration
            _disabledDisplayIds[newDisabledDisplayIdsCnt] = displayIds[i];
            newDisabledDisplayIdsCnt++;
            NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors add disabled id=%u newCnt=%d]", displayIds[i], newDisabledDisplayIdsCnt);
        }
        else {
            NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors skip duplicate id=%u]", displayIds[i]);
        }
    }
    
    // Apply configuration
    CGError completeErr = CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
    if (completeErr != kCGErrorSuccess) {
        NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors failed reason=complete err=%d oldCnt=%d newCnt=%d]", completeErr, _disabledDisplayIdsCnt, newDisabledDisplayIdsCnt);
        free(displayIds);
        return false;
    }
    
    _disabledDisplayIdsCnt = newDisabledDisplayIdsCnt;
    NSLog(@"[VirtualMonDebugMsg : DisableOtherMonitors success disabledCnt=%d]", _disabledDisplayIdsCnt);
    
    free(displayIds);

    return true;
}

bool VirtualMonitor::IsVirtualDisplay(CGDirectDisplayID displayId) {
    if (displayId == 0) {
        return false;
    }

    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        if (_virtualDisplayInfo[i].virtualDisplay == nil) {
            continue;
        }

        if (_virtualDisplayInfo[i].virtualDisplay.displayID == displayId) {
            return true;
        }
    }

    return false;
}

bool VirtualMonitor::IsAllVirtualDisplayOnline() {
    if (_virtualDisplayInfoCnt <= 0) {
        return false;
    }

    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        if (_virtualDisplayInfo[i].virtualDisplay == nil) {
            return false;
        }

        if (DisplayUtils::IsDisplayOnline(_virtualDisplayInfo[i].virtualDisplay.displayID) == false) {
            return false;
        }
    }

    return true;
}

int VirtualMonitor::GetPrimaryDisplayIndex() {
    if (_virtualDisplayInfoCnt <= 0) {
        return -1;
    }

    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        if (_virtualDisplayInfo[i].is_primary != 0) {
            return i;
        }
    }

    return 0;
}

bool VirtualMonitor::IsRightPrimaryDisplay() {
    int primaryIndex = GetPrimaryDisplayIndex();
    if (primaryIndex < 0 || primaryIndex >= _virtualDisplayInfoCnt) {
        return false;
    }

    if (_virtualDisplayInfo[primaryIndex].virtualDisplay == nil) {
        return false;
    }

    return CGMainDisplayID() == _virtualDisplayInfo[primaryIndex].virtualDisplay.displayID;
}

bool VirtualMonitor::IsRightDisplayLayout() {
    int primaryIndex = GetPrimaryDisplayIndex();
    if (primaryIndex < 0 || primaryIndex >= _virtualDisplayInfoCnt) {
        return false;
    }

    struct VIRTUALMONITOR_INFO* primaryInfo = &_virtualDisplayInfo[primaryIndex];
    if (primaryInfo->virtualDisplay == nil) {
        return false;
    }

    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        struct VIRTUALMONITOR_INFO* displayInfo = &_virtualDisplayInfo[i];
        if (displayInfo->virtualDisplay == nil) {
            return false;
        }

        CGRect bounds = CGDisplayBounds(displayInfo->virtualDisplay.displayID);
        int expectedX = displayInfo->left - primaryInfo->left;
        int expectedY = displayInfo->top - primaryInfo->top;

        if ((int)bounds.origin.x != expectedX || (int)bounds.origin.y != expectedY) {
            return false;
        }
    }

    return IsRightPrimaryDisplay();
}

int VirtualMonitor::SetResolution(int index) {
    if (index < 0 || index >= _virtualDisplayInfoCnt) {
        return 1;
    }

    struct VIRTUALMONITOR_INFO* displayInfo = &_virtualDisplayInfo[index];
    if (displayInfo->virtualDisplay == nil) {
        return 1;
    }

    CGDisplayModeRef bestMode = NULL;
    
    // Option to include Retina (HiDPI) resolutions
    CFStringRef keys[1] = { kCGDisplayShowDuplicateLowResolutionModes };
    CFTypeRef values[1] = { kCFBooleanTrue };
        
    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault,
        (const void **)keys,
        (const void **)values,
        1,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
        
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(displayInfo->virtualDisplay.displayID, options);
    if (modes == NULL) {
        NSLog(@"[VirtualMonitor::SetResolution] CGDisplayCopyAllDisplayModes null\n");
        CFRelease(options);
        
        return 1;
    }
    
    if (displayInfo->is_retina) {
        CFIndex cnt = CFArrayGetCount(modes);
        // Find Retina (HiDPI) resolution first
        for (CFIndex i = 0; i < cnt; i++) {
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            
            size_t modeWidth = CGDisplayModeGetWidth(mode);
            size_t modeHeight = CGDisplayModeGetHeight(mode);
            
            if (modeWidth == (displayInfo->width / 2) && modeHeight == (displayInfo->height / 2)) {
                NSLog(@"found retina bestmode\n");
                bestMode = mode;
                break;
            }
        }
        
        // If no Retina resolution found, find regular resolution
        if (bestMode == NULL) {
            CFIndex cnt = CFArrayGetCount(modes);
            for (CFIndex i = 0; i < cnt; i++) {
                CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                
                size_t modeWidth = CGDisplayModeGetWidth(mode);
                size_t modeHeight = CGDisplayModeGetHeight(mode);
                
                if (modeWidth == displayInfo->width && modeHeight == displayInfo->height) {
                    NSLog(@"found bestmode\n");
                    bestMode = mode;
                    break;
                }
            }
        }
    }
    else {
        CFIndex cnt = CFArrayGetCount(modes);
        for (CFIndex i = 0; i < cnt; i++) {
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            
            size_t modeWidth = CGDisplayModeGetWidth(mode);
            size_t modeHeight = CGDisplayModeGetHeight(mode);
            
            if (modeWidth == displayInfo->width && modeHeight == displayInfo->height) {
                NSLog(@"found bestmode\n");
                bestMode = mode;
                break;
            }
        }
    }
    
    if (bestMode == NULL) {
        NSLog(@"bestmode is null\n");
        
        CFRelease(modes);
        CFRelease(options);
        
        return 1;
    }
    
    CGError err = CGDisplaySetDisplayMode(displayInfo->virtualDisplay.displayID, bestMode, NULL);
    if (err != kCGErrorSuccess) {
        printf("Configure Resolution Failed. %d \n", err);
    }
    
    CFRelease(modes);
    CFRelease(options);
    
    return err == kCGErrorSuccess ? 0 : 1;
}

bool VirtualMonitor::IsRightResolution(int index) {
    if (index < 0 || index >= _virtualDisplayInfoCnt) {
        return false;
    }
    
    struct VIRTUALMONITOR_INFO* displayInfo = &_virtualDisplayInfo[index];
    if (displayInfo->virtualDisplay == nil) {
        return false;
    }

    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayInfo->virtualDisplay.displayID);
    if (mode == NULL) {
        return false;
    }
    
    size_t modeWidth = CGDisplayModeGetWidth(mode);
    size_t modeHeight = CGDisplayModeGetHeight(mode);
    size_t pixelWidth = CGDisplayModeGetPixelWidth(mode);
    size_t pixelHeight = CGDisplayModeGetPixelHeight(mode);
    
    bool result = false;
    if (displayInfo->is_retina) {
        result = (modeWidth == (displayInfo->width / 2) && modeHeight == (displayInfo->height / 2) &&
                  pixelWidth == displayInfo->width && pixelHeight == displayInfo->height);
    }
    else {
        result = (modeWidth == displayInfo->width && modeHeight == displayInfo->height &&
                  pixelWidth == displayInfo->width && pixelHeight == displayInfo->height);
    }
    
    CFRelease(mode);
    
    return result;
}

int VirtualMonitor::SetPrimaryDisplay() {
    int primaryIndex = GetPrimaryDisplayIndex();
    if (primaryIndex < 0 || primaryIndex >= _virtualDisplayInfoCnt) {
        return 1;
    }

    struct VIRTUALMONITOR_INFO* primaryInfo = &_virtualDisplayInfo[primaryIndex];
    if (primaryInfo->virtualDisplay == nil) {
        return 1;
    }

    CGDirectDisplayID primaryDisplayId = primaryInfo->virtualDisplay.displayID;
    if (primaryDisplayId == 0) {
        return 1;
    }

    CGRect primaryBounds = CGDisplayBounds(primaryDisplayId);
    int offsetX = -(int)primaryBounds.origin.x;
    int offsetY = -(int)primaryBounds.origin.y;

    if (offsetX == 0 && offsetY == 0 && CGMainDisplayID() == primaryDisplayId) {
        return 0;
    }

    uint32_t displayCnt = 0;
    CGError displayListErr = CGGetOnlineDisplayList(0, NULL, &displayCnt);
    if (displayListErr != kCGErrorSuccess || displayCnt == 0) {
        NSLog(@"[VirtualMonitor::SetPrimaryDisplay] failed reason=noDisplay err=%d cnt=%u", displayListErr, displayCnt);
        return 1;
    }

    CGDirectDisplayID* displayIds = (CGDirectDisplayID*)malloc(sizeof(CGDirectDisplayID) * displayCnt);
    if (displayIds == NULL) {
        NSLog(@"[VirtualMonitor::SetPrimaryDisplay] failed reason=mallocDisplayIds cnt=%u", displayCnt);
        return 1;
    }

    displayListErr = CGGetOnlineDisplayList(displayCnt, displayIds, NULL);
    if (displayListErr != kCGErrorSuccess) {
        NSLog(@"[VirtualMonitor::SetPrimaryDisplay] failed reason=getDisplayList err=%d cnt=%u", displayListErr, displayCnt);
        free(displayIds);
        return 1;
    }

    CGDisplayConfigRef cfg = NULL;
    CGError beginErr = CGBeginDisplayConfiguration(&cfg);
    if (beginErr != kCGErrorSuccess || cfg == NULL) {
        NSLog(@"[VirtualMonitor::SetPrimaryDisplay] failed reason=beginConfiguration err=%d cfg=%p", beginErr, cfg);
        free(displayIds);
        return 1;
    }

    bool configured = true;
    for (uint32_t i = 0; i < displayCnt; i++) {
        CGRect bounds = CGDisplayBounds(displayIds[i]);
        int x = (int)bounds.origin.x + offsetX;
        int y = (int)bounds.origin.y + offsetY;

        CGError configureErr = CGConfigureDisplayOrigin(cfg, displayIds[i], x, y);
        if (configureErr != kCGErrorSuccess) {
            NSLog(@"[VirtualMonitor::SetPrimaryDisplay] configure failed id=%u err=%d", displayIds[i], configureErr);
            configured = false;
            break;
        }
    }

    if (configured == false) {
        CGCancelDisplayConfiguration(cfg);
        free(displayIds);
        return 1;
    }

    CGError completeErr = CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
    free(displayIds);

    if (completeErr != kCGErrorSuccess) {
        NSLog(@"[VirtualMonitor::SetPrimaryDisplay] failed reason=complete err=%d", completeErr);
        return 1;
    }

    NSLog(@"[VirtualMonitor::SetPrimaryDisplay] success primary=%u", primaryDisplayId);
    return 0;
}

int VirtualMonitor::ApplyDisplayLayout() {
    int primaryIndex = GetPrimaryDisplayIndex();
    if (primaryIndex < 0 || primaryIndex >= _virtualDisplayInfoCnt) {
        return 1;
    }

    struct VIRTUALMONITOR_INFO* primaryInfo = &_virtualDisplayInfo[primaryIndex];
    if (primaryInfo->virtualDisplay == nil) {
        return 1;
    }

    CGDisplayConfigRef cfg = NULL;
    CGError beginErr = CGBeginDisplayConfiguration(&cfg);
    if (beginErr != kCGErrorSuccess || cfg == NULL) {
        NSLog(@"[VirtualMonitor::ApplyDisplayLayout] failed reason=beginConfiguration err=%d cfg=%p", beginErr, cfg);
        return 1;
    }

    bool configured = true;
    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        struct VIRTUALMONITOR_INFO* displayInfo = &_virtualDisplayInfo[i];
        if (displayInfo->virtualDisplay == nil) {
            configured = false;
            break;
        }

        int x = displayInfo->left - primaryInfo->left;
        int y = displayInfo->top - primaryInfo->top;

        CGError configureErr = CGConfigureDisplayOrigin(cfg, displayInfo->virtualDisplay.displayID, x, y);
        if (configureErr != kCGErrorSuccess) {
            NSLog(@"[VirtualMonitor::ApplyDisplayLayout] configure failed index=%d id=%u x=%d y=%d err=%d",
                  i, displayInfo->virtualDisplay.displayID, x, y, configureErr);
            configured = false;
            break;
        }
    }

    if (configured == false) {
        CGCancelDisplayConfiguration(cfg);
        return 1;
    }

    CGError completeErr = CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
    if (completeErr != kCGErrorSuccess) {
        NSLog(@"[VirtualMonitor::ApplyDisplayLayout] failed reason=complete err=%d", completeErr);
        return 1;
    }

    NSLog(@"[VirtualMonitor::ApplyDisplayLayout] success primaryIndex=%d primary=%u", primaryIndex, primaryInfo->virtualDisplay.displayID);
    return 0;
}

void* VirtualMonitor::WatchThreadProc(void* args) {
    
    if (args == NULL) return NULL;
    VirtualMonitor* _this = (VirtualMonitor*)args;
    
    pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
    
    pthread_mutex_lock(&_this->_watchLock);
    
    for(;;) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += 3;
        
        pthread_cond_timedwait(&_this->_watchWake, &_this->_watchLock, &ts);
        
        if (_this->_watchRunning == false) break;
        
        _this->WatchThreadPorcInternal();
    }
    
    pthread_mutex_unlock(&_this->_watchLock);
    
    return NULL;
}

void VirtualMonitor::WatchThreadPorcInternal() {
    // Virtual monitor not yet fully activated
    if (_init == false) {
        // Check if all virtual monitors are fully available
        if (IsAllVirtualDisplayOnline() == false) {
            NSLog(@"[VirtualMonitor::WatchThreadProc] virtual display does not online yet");
            return;
        }
        
        NSLog(@"[VirtualMonitor::WatchThreadProc] virtual display has been online now");
        _init = true;
    }
    
    // Check if other monitors besides virtual monitor are online
    DisableOtherMonitors();
    
    // Check resolution info (virtual monitor)
    for (int i = 0; i < _virtualDisplayInfoCnt; i++) {
        if (IsRightResolution(i) == false) {
            // If resolution is wrong (or not set yet) --> set resolution
            NSLog(@"[VirtualMonitor::WatchThreadProc] virtual display has invalid resolution. try change it index=%d", i);
            SetResolution(i);
        }
    }

    // Restore display layout and primary if changed during display add/remove
    if (IsRightDisplayLayout() == false) {
        NSLog(@"[VirtualMonitor::WatchThreadProc] virtual display has invalid layout. try change it");
        ApplyDisplayLayout();
    }
}
