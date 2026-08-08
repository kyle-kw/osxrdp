#import <Foundation/Foundation.h>

#include "ConnectionDiagnostics.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const OSXRDPConnectionStatusDidChangeNotification;

@interface ConnectionStatusCoordinator : NSObject

@property (class, readonly, strong) ConnectionStatusCoordinator *shared;
@property (readonly) BOOL desiredRunning;
@property (readonly, getter=isStarting) BOOL starting;

- (ConnectionDiagnosticsSnapshot)currentSnapshot;
- (ConnectionState)currentState;
- (void)startMonitoring;
- (void)stopMonitoring;
- (void)refreshNow;
- (void)startService;
- (void)stopService;

@end

NS_ASSUME_NONNULL_END
