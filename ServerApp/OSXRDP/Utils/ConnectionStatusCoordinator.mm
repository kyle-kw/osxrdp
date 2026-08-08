#import "ConnectionStatusCoordinator.h"

#include "../RemoteConnection/RemoteConnectionService.h"

NSNotificationName const OSXRDPConnectionStatusDidChangeNotification = @"OSXRDPConnectionStatusDidChangeNotification";

@interface ConnectionStatusCoordinator ()

@property (assign) BOOL desiredRunning;
@property (assign, getter=isStarting) BOOL starting;
@property (strong) NSTimer *refreshTimer;
@property (assign) BOOL monitoring;
@property (assign) BOOL lastPermissionsGranted;

@end

@implementation ConnectionStatusCoordinator {
    ConnectionDiagnosticsSnapshot _snapshot;
}

+ (instancetype)shared {
    static ConnectionStatusCoordinator *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ConnectionStatusCoordinator alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _desiredRunning = YES;
        _starting = NO;
        _monitoring = NO;
        _snapshot = ConnectionDiagnostics::Capture();
        _lastPermissionsGranted = _snapshot.accessibilityGranted && _snapshot.screenRecordingGranted;
    }
    return self;
}

- (ConnectionDiagnosticsSnapshot)currentSnapshot {
    return _snapshot;
}

- (ConnectionState)currentState {
    if (self.isStarting) {
        return ConnectionState::Starting;
    }
    return _snapshot.state;
}

- (void)startMonitoring {
    if (self.monitoring) {
        return;
    }

    self.monitoring = YES;
    [self captureAndPublish];

    BOOL permissionsGranted = _snapshot.accessibilityGranted && _snapshot.screenRecordingGranted;
    self.lastPermissionsGranted = permissionsGranted;
    if (ConnectionShouldStartOnLaunch(self.desiredRunning, permissionsGranted, _snapshot.agentRunning)) {
        [self startService];
    }

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(refreshNow)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopMonitoring {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    self.monitoring = NO;
}

- (void)refreshNow {
    BOOL hadPermissions = self.lastPermissionsGranted;
    [self captureAndPublish];

    BOOL permissionsGranted = _snapshot.accessibilityGranted && _snapshot.screenRecordingGranted;
    self.lastPermissionsGranted = permissionsGranted;
    if (self.monitoring && ConnectionShouldAutoStartAfterRefresh(self.desiredRunning,
                                                                 hadPermissions,
                                                                 permissionsGranted,
                                                                 _snapshot.agentRunning,
                                                                 self.isStarting)) {
        [self startService];
    }
}

- (void)startService {
    self.desiredRunning = YES;
    [self captureAndPublish];
    if (!_snapshot.accessibilityGranted || !_snapshot.screenRecordingGranted || _snapshot.agentRunning) {
        return;
    }

    self.starting = YES;
    [self publishCurrentSnapshot];
    StartRemoteConnectionServerService();
    self.starting = NO;
    [self captureAndPublish];
}

- (void)stopService {
    self.desiredRunning = NO;
    StopRemoteConnectionServerService();
    self.starting = NO;
    [self captureAndPublish];
}

- (void)captureAndPublish {
    _snapshot = ConnectionDiagnostics::Capture();
    [self publishCurrentSnapshot];
}

- (void)publishCurrentSnapshot {
    [[NSNotificationCenter defaultCenter] postNotificationName:OSXRDPConnectionStatusDidChangeNotification
                                                        object:self];
}

@end
