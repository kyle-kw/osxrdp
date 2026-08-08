#import "AppDelegate.h"

#include <signal.h>

#import "Clipboard/ClipboardManager.h"
#include "RemoteConnection/RemoteConnectionService.h"
#include "Utils/ConnectionStatusCoordinator.h"
#import "UI/Main/MainWindowController.h"
#import "UI/Settings/SettingsWindow.h"

@interface AppDelegate ()
{
    NSStatusItem *_statusItem;
    NSMenuItem *_statusSummaryMenuItem;
    NSMenuItem *_serviceActionMenuItem;
    NSMenuItem *_saveCopiedFilesMenuItem;
    NSMenuItem *_saveToDownloadsMenuItem;
    dispatch_source_t _sigSource;
}

@property (strong) SettingsWindow *settingsWindow;
@property (strong) IBOutlet MainWindowController *mainWindowController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    signal(SIGTERM, SIG_IGN);
    _sigSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(_sigSource, ^{
        NSLog(@"[OSXRDP] Received SIGTERM");
        StopRemoteConnectionServerService();
        exit(0);
    });
    dispatch_resume(_sigSource);

    extern int g_Lockscreen;
    if (g_Lockscreen == 1) {
        sleep(2);
        StartRemoteConnectionServerService();
        return;
    }

    [self setupStatusBar];
    [self.mainWindowController initializeMainUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(connectionStatusDidChange:)
                                                 name:OSXRDPConnectionStatusDidChangeNotification
                                               object:ConnectionStatusCoordinator.shared];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteFilesDidChange:)
                                                 name:OSXRDPRemoteFilesAvailableNotification
                                               object:nil];

    [ConnectionStatusCoordinator.shared startMonitoring];
    [self refreshStatusBar];
    if ([ConnectionStatusCoordinator.shared currentState] == ConnectionState::NeedsPermissions) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self onOpenDashboardMenuClicked];
        });
    }
    (void)notification;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [ConnectionStatusCoordinator.shared stopMonitoring];
    StopRemoteConnectionServerService();
    (void)notification;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [ConnectionStatusCoordinator.shared refreshNow];
    (void)notification;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
    [self onOpenDashboardMenuClicked];
    (void)application;
    (void)hasVisibleWindows;
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    (void)app;
    return NO;
}

- (void)setupStatusBar {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSMenu *menu = [[NSMenu alloc] init];

    _statusSummaryMenuItem = [menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    _statusSummaryMenuItem.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *dashboardItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.dashboard", nil)
                                                action:@selector(onOpenDashboardMenuClicked)
                                         keyEquivalent:@""];
    dashboardItem.target = self;
    _serviceActionMenuItem = [menu addItemWithTitle:@""
                                            action:@selector(onServiceActionMenuClicked)
                                     keyEquivalent:@""];
    _serviceActionMenuItem.target = self;

    [menu addItem:NSMenuItem.separatorItem];
    _saveToDownloadsMenuItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.save_to_downloads", nil)
                                                action:@selector(onSaveToDownloadsMenuClicked)
                                         keyEquivalent:@""];
    _saveToDownloadsMenuItem.target = self;
    _saveCopiedFilesMenuItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.save_copied_files", nil)
                                                action:@selector(onSaveCopiedFilesMenuClicked)
                                         keyEquivalent:@""];
    _saveCopiedFilesMenuItem.target = self;

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settingsItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.settings", nil)
                                               action:@selector(onSettingsMenuClicked)
                                        keyEquivalent:@""];
    settingsItem.target = self;
    NSMenuItem *aboutItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.about", nil)
                                            action:@selector(onAboutMenuClicked)
                                     keyEquivalent:@""];
    aboutItem.target = self;

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quitItem = [menu addItemWithTitle:NSLocalizedString(@"statusbar.menu.quit", nil)
                                           action:@selector(onExitMenuClicked)
                                    keyEquivalent:@""];
    quitItem.target = self;
    _statusItem.menu = menu;
}

- (void)connectionStatusDidChange:(NSNotification *)notification {
    [self refreshStatusBar];
    (void)notification;
}

- (void)remoteFilesDidChange:(NSNotification *)notification {
    [ConnectionStatusCoordinator.shared refreshNow];
    (void)notification;
}

- (void)refreshStatusBar {
    ConnectionStatusCoordinator *coordinator = ConnectionStatusCoordinator.shared;
    ConnectionDiagnosticsSnapshot snap = [coordinator currentSnapshot];
    ConnectionState state = [coordinator currentState];

    NSString *stateTitle = [self titleForState:state];
    _statusSummaryMenuItem.title =
        [NSString stringWithFormat:NSLocalizedString(@"statusbar.menu.status_summary", nil), stateTitle];

    NSColor *color = NSColor.secondaryLabelColor;
    switch (state) {
        case ConnectionState::NeedsPermissions:
        case ConnectionState::Starting:
            color = NSColor.systemOrangeColor;
            break;
        case ConnectionState::Ready:
            color = NSColor.systemGreenColor;
            break;
        case ConnectionState::Connected:
            color = NSColor.systemBlueColor;
            break;
        case ConnectionState::Stopped:
            color = NSColor.secondaryLabelColor;
            break;
        case ConnectionState::Failed:
            color = NSColor.systemRedColor;
            break;
    }

    NSImage *image = [NSImage imageWithSystemSymbolName:@"bolt.horizontal.circle.fill"
                              accessibilityDescription:NSLocalizedString(@"statusbar.icon.accessibility", nil)];
    if (@available(macOS 12.0, *)) {
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    }
    _statusItem.button.image = image;

    switch (ConnectionPrimaryActionForState(state)) {
        case ConnectionPrimaryAction::None:
            _serviceActionMenuItem.title = NSLocalizedString(@"main.action.starting", nil);
            break;
        case ConnectionPrimaryAction::SetUpPermissions:
            _serviceActionMenuItem.title = NSLocalizedString(@"main.action.permissions", nil);
            break;
        case ConnectionPrimaryAction::StartService:
            _serviceActionMenuItem.title = NSLocalizedString(@"main.action.start", nil);
            break;
        case ConnectionPrimaryAction::StopService:
            _serviceActionMenuItem.title = NSLocalizedString(@"main.action.stop", nil);
            break;
        case ConnectionPrimaryAction::Retry:
            _serviceActionMenuItem.title = NSLocalizedString(@"main.action.retry", nil);
            break;
    }

    if (snap.remoteFileCount > 0) {
        _saveCopiedFilesMenuItem.title =
            [NSString stringWithFormat:NSLocalizedString(@"statusbar.menu.save_copied_files_count", nil), snap.remoteFileCount];
        _saveToDownloadsMenuItem.title =
            [NSString stringWithFormat:NSLocalizedString(@"statusbar.menu.save_to_downloads_count", nil), snap.remoteFileCount];
    } else {
        _saveCopiedFilesMenuItem.title = NSLocalizedString(@"statusbar.menu.save_copied_files", nil);
        _saveToDownloadsMenuItem.title = NSLocalizedString(@"statusbar.menu.save_to_downloads", nil);
    }

    if (snap.rdpClientConnected) {
        NSString *codec = snap.currentCodecBuf[0] != '\0' ? [NSString stringWithUTF8String:snap.currentCodecBuf] : @"—";
        _statusItem.button.toolTip = [NSString stringWithFormat:@"%@\n%d × %d · %@ · %d fps",
                                      stateTitle, snap.currentWidth, snap.currentHeight,
                                      codec, snap.currentFramerate];
    } else {
        _statusItem.button.toolTip = stateTitle;
    }
}

- (NSString *)titleForState:(ConnectionState)state {
    switch (state) {
        case ConnectionState::NeedsPermissions:
            return NSLocalizedString(@"statusbar.state.permissions", nil);
        case ConnectionState::Starting:
            return NSLocalizedString(@"statusbar.state.starting", nil);
        case ConnectionState::Ready:
            return NSLocalizedString(@"statusbar.state.ready", nil);
        case ConnectionState::Connected:
            return NSLocalizedString(@"statusbar.state.connected", nil);
        case ConnectionState::Stopped:
            return NSLocalizedString(@"statusbar.state.stopped", nil);
        case ConnectionState::Failed:
            return NSLocalizedString(@"statusbar.state.failed", nil);
    }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    id object = (id)item;
    if (![object isKindOfClass:NSMenuItem.class]) {
        return YES;
    }
    NSMenuItem *menuItem = (NSMenuItem *)object;
    if (menuItem == _saveCopiedFilesMenuItem || menuItem == _saveToDownloadsMenuItem) {
        ConnectionDiagnosticsSnapshot snap = [ConnectionStatusCoordinator.shared currentSnapshot];
        return snap.remoteFileCount > 0;
    }
    if (menuItem == _serviceActionMenuItem) {
        return [ConnectionStatusCoordinator.shared currentState] != ConnectionState::Starting;
    }
    return YES;
}

- (void)onOpenDashboardMenuClicked {
    [NSApp activateIgnoringOtherApps:YES];
    [self.mainWindowController showMainWindow];
}

- (void)onServiceActionMenuClicked {
    ConnectionStatusCoordinator *coordinator = ConnectionStatusCoordinator.shared;
    ConnectionState state = [coordinator currentState];
    switch (ConnectionPrimaryActionForState(state)) {
        case ConnectionPrimaryAction::SetUpPermissions:
            [NSApp activateIgnoringOtherApps:YES];
            [self.mainWindowController showPermissionSetup];
            break;
        case ConnectionPrimaryAction::StartService:
        case ConnectionPrimaryAction::Retry:
            [coordinator startService];
            break;
        case ConnectionPrimaryAction::StopService:
            if (state == ConnectionState::Connected && ![self confirmActiveDisconnectWithQuit:NO]) {
                return;
            }
            [coordinator stopService];
            break;
        case ConnectionPrimaryAction::None:
            break;
    }
}

- (void)onSettingsMenuClicked {
    [self showSettings];
}

- (void)showSettings {
    [NSApp activateIgnoringOtherApps:YES];
    if (self.settingsWindow != nil && self.settingsWindow.window.isVisible) {
        [self.settingsWindow.window makeKeyAndOrderFront:nil];
        return;
    }

    self.settingsWindow = [[SettingsWindow alloc] init];
    NSWindow *settings = self.settingsWindow.window;
    __weak AppDelegate *weakSelf = self;
    self.settingsWindow.onClose = ^{
        weakSelf.settingsWindow = nil;
    };

    NSWindow *host = self.mainWindowController.window;
    if (host != nil && host.isVisible) {
        [host beginSheet:settings completionHandler:^(NSModalResponse returnCode) {
            (void)returnCode;
            weakSelf.settingsWindow = nil;
        }];
    } else {
        [settings center];
        [settings makeKeyAndOrderFront:nil];
    }
}

- (void)onAboutMenuClicked {
    NSString *creditsText = NSLocalizedString(@"about.credits", nil);
    NSMutableAttributedString *credits = [[NSMutableAttributedString alloc] initWithString:creditsText];
    NSRange projectRange = [creditsText rangeOfString:@"GitHub"];
    if (projectRange.location != NSNotFound) {
        [credits addAttribute:NSLinkAttributeName
                       value:@"https://github.com/bho3538/osxrdp"
                       range:projectRange];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionCredits: credits,
        NSAboutPanelOptionApplicationName: @"OSXRDP",
    }];
}

- (void)onExitMenuClicked {
    ConnectionDiagnosticsSnapshot snap = [ConnectionStatusCoordinator.shared currentSnapshot];
    if (snap.rdpClientConnected && ![self confirmActiveDisconnectWithQuit:YES]) {
        return;
    }
    [NSApp terminate:nil];
}

- (BOOL)confirmActiveDisconnectWithQuit:(BOOL)quit {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = quit
        ? NSLocalizedString(@"statusbar.quit.confirm.title", nil)
        : NSLocalizedString(@"main.stop.confirm.title", nil);
    alert.informativeText = NSLocalizedString(@"statusbar.quit.confirm.message", nil);
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:NSLocalizedString(@"common.cancel", nil)];
    [alert addButtonWithTitle:quit
        ? NSLocalizedString(@"statusbar.menu.quit", nil)
        : NSLocalizedString(@"main.action.stop", nil)];
    return [alert runModal] == NSAlertSecondButtonReturn;
}

- (void)onSaveCopiedFilesMenuClicked {
    StartRemoteClipboardFileCopy();
}

- (void)onSaveToDownloadsMenuClicked {
    StartRemoteClipboardFileCopyToDownloads();
}

@end
