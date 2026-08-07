#import "AppDelegate.h"

#include <signal.h>
#include "RemoteConnection/RemoteConnectionService.h"
#include "Utils/ConnectionDiagnostics.h"
#import "Clipboard/ClipboardManager.h"

#import "UI/Main/MainWindowController.h"


@interface AppDelegate ()
{
    NSStatusItem* _trayMenu;
    NSMenuItem* _saveCopiedFilesMenuItem;
    NSMenuItem* _saveToDownloadsMenuItem;
    NSMenuItem* _statusMenuItem;
    dispatch_source_t _sigSource;
    NSTimer* _trayRefreshTimer;
}

@property (strong) IBOutlet MainWindowController* mainWindowController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    signal(SIGTERM, SIG_IGN);
    _sigSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(_sigSource, ^{
        NSLog(@"[OSXRDP] on sigterm");
        StopRemoteConnectionServerService();
        exit(0);
    });
    dispatch_resume(_sigSource);

    extern int g_Lockscreen;
    if (g_Lockscreen == 1) {
        // hack
        sleep(2);
        
        StartRemoteConnectionServerService();
        return;
    }

    [self setupStatusBar];
    [self.mainWindowController initializeMainUI];
    [self refreshTrayState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onRemoteFilesAvailable:)
                                                 name:OSXRDPRemoteFilesAvailableNotification
                                               object:nil];

    // Single refresh source for the tray (main window has its own statusTimer).
    _trayRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(refreshTrayState)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_trayRefreshTimer invalidate];
    _trayRefreshTimer = nil;
    StopRemoteConnectionServerService();
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self refreshTrayState];
    (void)notification;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return NO;
}

- (void)setupStatusBar {
    _trayMenu = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];

    NSImage* img = [NSImage imageWithSystemSymbolName:@"bolt.horizontal.circle.fill" accessibilityDescription:NSLocalizedString(@"statusbar.icon.accessibility", nil)];
    _trayMenu.button.image = img;

    NSMenu* menus = [[NSMenu alloc] init];
    [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.title", nil) action:nil keyEquivalent:@""];
    
    [menus addItem:NSMenuItem.separatorItem];
    
    NSMenuItem* openItem = [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.open", nil) action:@selector(onOpenWindowMenuClicked) keyEquivalent:@""];
    openItem.target = self;

    _statusMenuItem = [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.status", nil) action:@selector(onStatusMenuClicked) keyEquivalent:@""];
    _statusMenuItem.target = self;

    [menus addItem:NSMenuItem.separatorItem];

    _saveToDownloadsMenuItem = [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.save_to_downloads", nil) action:@selector(onSaveToDownloadsMenuClicked) keyEquivalent:@""];
    _saveToDownloadsMenuItem.target = self;

    _saveCopiedFilesMenuItem = [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.save_copied_files", nil) action:@selector(onSaveCopiedFilesMenuClicked) keyEquivalent:@""];
    _saveCopiedFilesMenuItem.target = self;
    
    [menus addItem:NSMenuItem.separatorItem];
    
    NSMenuItem* closeItem = [menus addItemWithTitle:NSLocalizedString(@"statusbar.menu.close", nil) action:@selector(onExitMenuClicked) keyEquivalent:@""];
    closeItem.target = self;

    _trayMenu.menu = menus;
}

- (void)refreshTrayState {
    ConnectionDiagnosticsSnapshot snap = ConnectionDiagnostics::Capture();

    NSImage* img = [NSImage imageWithSystemSymbolName:@"bolt.horizontal.circle.fill"
                             accessibilityDescription:NSLocalizedString(@"statusbar.icon.accessibility", nil)];
    if (@available(macOS 12.0, *)) {
        if (snap.overallState == 0) {
            img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor systemGreenColor]]];
        } else if (snap.overallState == 1) {
            img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor systemOrangeColor]]];
        } else {
            img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor systemRedColor]]];
        }
    }
    _trayMenu.button.image = img;
    // Keep the item clickable; color already encodes health (green/orange/red).

    int count = snap.remoteFileCount;
    if (count > 0) {
        _saveCopiedFilesMenuItem.title =
            [NSString stringWithFormat:NSLocalizedString(@"statusbar.menu.save_copied_files_count", nil), count];
        _saveToDownloadsMenuItem.title =
            [NSString stringWithFormat:NSLocalizedString(@"statusbar.menu.save_to_downloads_count", nil), count];
    } else {
        _saveCopiedFilesMenuItem.title = NSLocalizedString(@"statusbar.menu.save_copied_files", nil);
        _saveToDownloadsMenuItem.title = NSLocalizedString(@"statusbar.menu.save_to_downloads", nil);
    }
}

- (void)onRemoteFilesAvailable:(NSNotification*)notification {
    [self refreshTrayState];
    (void)notification;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem == _saveCopiedFilesMenuItem || menuItem == _saveToDownloadsMenuItem) {
        return HasRemoteClipboardFiles();
    }

    return YES;
}

- (void)onOpenWindowMenuClicked {
    [NSApp activateIgnoringOtherApps:YES];
    [self.mainWindowController showMainWindow];
}

- (void)onStatusMenuClicked {
    // Open the main window status panel only (avoid stacking a duplicate modal alert).
    [self onOpenWindowMenuClicked];
}

- (void)onExitMenuClicked {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert* alert = [[NSAlert alloc] init];
    if (alert == nil) {
        return;
    }

    [alert setMessageText:NSLocalizedString(@"statusbar.quit.confirm.title", nil)];
    [alert setInformativeText:NSLocalizedString(@"statusbar.quit.confirm.message", nil)];
    [alert setAlertStyle:NSAlertStyleWarning];
    NSButton* noButton = [alert addButtonWithTitle:NSLocalizedString(@"statusbar.quit.confirm.no", nil)];
    NSButton* yesButton = [alert addButtonWithTitle:NSLocalizedString(@"statusbar.quit.confirm.yes", nil)];
    [noButton setKeyEquivalent:@"\r"];
    [yesButton setKeyEquivalent:@""];

    if ([alert runModal] != NSAlertSecondButtonReturn) {
        return;
    }

    [[NSApplication sharedApplication] terminate:nil];
}

- (void)onSaveCopiedFilesMenuClicked {
    StartRemoteClipboardFileCopy();
}

- (void)onSaveToDownloadsMenuClicked {
    StartRemoteClipboardFileCopyToDownloads();
}

@end
