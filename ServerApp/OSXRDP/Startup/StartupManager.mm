#include "StartupManager.h"

#import <ServiceManagement/ServiceManagement.h>
#import <AppKit/AppKit.h>

static NSString *const StartupManagerErrorDomain = @"com.byungho.osxrdp.startup";

StartupStatus StartupManager::GetStatus() {
    if (@available(macOS 13.0, *)) {
        switch ([SMAppService mainAppService].status) {
            case SMAppServiceStatusEnabled:
                return StartupStatus::Enabled;
            case SMAppServiceStatusRequiresApproval:
                return StartupStatus::RequiresApproval;
            case SMAppServiceStatusNotRegistered:
            case SMAppServiceStatusNotFound:
                return StartupStatus::Disabled;
        }
    }
    return StartupStatus::Unsupported;
}

bool StartupManager::SetEnabled(bool enabled, NSError* __autoreleasing* error) {
    if (@available(macOS 13.0, *)) {
        if (enabled) {
            return [[SMAppService mainAppService] registerAndReturnError:error] == YES;
        }
        return [[SMAppService mainAppService] unregisterAndReturnError:error] == YES;
    }

    if (error != nil) {
        *error = [NSError errorWithDomain:StartupManagerErrorDomain
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                NSLocalizedString(@"settings.startup.unsupported", nil)}];
    }
    return false;
}

void StartupManager::OpenLoginItemsSettings() {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.LoginItems-Settings.extension"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}
