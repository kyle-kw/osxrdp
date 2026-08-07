#ifndef DisplayUtils_h
#define DisplayUtils_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

class DisplayUtils {
public:
    // Check if display is online
    static bool IsDisplayOnline(CGDirectDisplayID displayId);
    
    // Check if there are other online displays besides the specified one
    static bool HasOtherOnlineDisplay(CGDirectDisplayID displayId);
    
    // Wait until display transitions to specified state (online/offline)
    static bool WaitDisplayOnlineState(CGDirectDisplayID displayId, bool shouldBeOnline, int timeoutMs);
    
    // Display on/off
    static bool ApplyDisplayEnabled(uint32_t* displayIds, int displayCnt, bool enabled);
};

#endif /* DisplayUtils_h */
