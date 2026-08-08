#ifndef StartupManager_h
#define StartupManager_h

#import <Foundation/Foundation.h>

enum class StartupStatus {
    Unsupported = 0,
    Disabled,
    RequiresApproval,
    Enabled,
};

class StartupManager
{
public:
  StartupManager() = default;
  ~StartupManager() = default;

  static StartupStatus GetStatus();
  static bool SetEnabled(bool enabled, NSError* __autoreleasing* error);
  static void OpenLoginItemsSettings();
};

#endif /* StartupManager_h */
