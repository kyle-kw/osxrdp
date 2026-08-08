
#include "PermissionCheckUtils.h"
#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>

bool PermissionCheckUtils::HasAccPermission() {
    return AXIsProcessTrustedWithOptions(nullptr) != 0 ? true : false;
}

bool PermissionCheckUtils::HasScreenRecordPermission() {
    return CGPreflightScreenCaptureAccess();
}

void PermissionCheckUtils::ShowAccPermissionRequestDialog() {
    CFDictionaryRef options = ::CFDictionaryCreate(
      kCFAllocatorDefault,
      (const void**)&kAXTrustedCheckOptionPrompt,
      (const void**)&kCFBooleanTrue,
      1,
      &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks
    );
    
    if (options == NULL)
    {
      return;
    }
    
    AXIsProcessTrustedWithOptions(options);
    
    CFRelease(options);
}

void PermissionCheckUtils::ShowScreenRecordPermissionRequestDialog() {
    CGRequestScreenCaptureAccess();
}

void PermissionCheckUtils::OpenAccPermissionSettings() {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

void PermissionCheckUtils::OpenScreenRecordPermissionSettings() {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

bool PermissionCheckUtils::HasAllPermissionToStartRemoteConnection() {
    return HasAccPermission() && HasScreenRecordPermission();
}
