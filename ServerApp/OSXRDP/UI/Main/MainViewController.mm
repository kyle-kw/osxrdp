#import "MainViewController.h"

#include "../../RemoteConnection/RemoteConnectionService.h"
#include "../../Startup/StartupManager.h"
#include "../../Utils/PermissionCheckUtils.h"
#include "../../Utils/ConnectionDiagnostics.h"

#import "../PermissionSettingsWindow.h"

@interface MainViewController ()

@property (strong) PermissionSettingsWindow* permSettingsWindow;
@property (strong) IBOutlet NSTextField* aboutLinkLabel;
@property (strong) IBOutlet NSButton* startRemoteConnectionBtn;
@property (strong) IBOutlet NSTextField* startupLabel;
@property (strong) IBOutlet NSSwitch* startupSwitch;
@property (assign) BOOL didConfigureInitialState;

@property (strong) NSTextField* statusAccessibilityLabel;
@property (strong) NSTextField* statusScreenLabel;
@property (strong) NSTextField* statusAgentLabel;
@property (strong) NSTextField* statusSessionLabel;
@property (strong) NSTextField* statusHintLabel;
@property (strong) NSButton* diagnoseButton;
@property (strong) NSTimer* statusTimer;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self installStatusPanelIfNeeded];
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self refreshStatusPanel];
    [self startStatusTimer];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [self stopStatusTimer];
}

- (void)configureInitialState {
    if (self.didConfigureInitialState == YES) {
        return;
    }

    self.didConfigureInitialState = YES;

    NSClickGestureRecognizer* click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(aboutUrlClicked:)];
    [self.aboutLinkLabel addGestureRecognizer:click];

    if (StartupManager::IsMacOS13OrHigher() == true) {
        if (StartupManager::IsStartupEnabled() == true) {
            [self.startupSwitch setState:NSControlStateValueOn];
        }
    } else {
        self.startupLabel.hidden = YES;
        self.startupSwitch.hidden = YES;
    }

    [self installStatusPanelIfNeeded];
    [self setDisabledBtnStyle:self.startRemoteConnectionBtn];
    [self startRemoteConnectionServer:YES];
    [self refreshStatusPanel];

    if (PermissionCheckUtils::HasAllPermissionToStartRemoteConnection() == false) {
        // Parent window must be visible before beginSheet, otherwise the sheet is not shown.
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp activateIgnoringOtherApps:YES];
            NSWindow* host = self.view.window;
            if (host != nil) {
                [host makeKeyAndOrderFront:nil];
                [host orderFrontRegardless];
            }
            [self openPermissionWindowBtnClicked:nil];
        });
    }
}

- (void)installStatusPanelIfNeeded {
    if (self.statusAccessibilityLabel != nil || self.view == nil) {
        return;
    }

    NSFont* font = [NSFont systemFontOfSize:12.0];
    CGFloat width = MAX(self.view.bounds.size.width - 40.0, 280.0);
    CGFloat y = 24.0;

    self.statusHintLabel = [self makeStatusLabelWithFont:font frame:NSMakeRect(20, y, width, 36)];
    self.statusHintLabel.textColor = [NSColor secondaryLabelColor];
    y += 40;

    self.statusSessionLabel = [self makeStatusLabelWithFont:font frame:NSMakeRect(20, y, width, 18)];
    y += 20;
    self.statusAgentLabel = [self makeStatusLabelWithFont:font frame:NSMakeRect(20, y, width, 18)];
    y += 20;
    self.statusScreenLabel = [self makeStatusLabelWithFont:font frame:NSMakeRect(20, y, width, 18)];
    y += 20;
    self.statusAccessibilityLabel = [self makeStatusLabelWithFont:font frame:NSMakeRect(20, y, width, 18)];
    y += 28;

    self.diagnoseButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 160, 28)];
    [self.diagnoseButton setBezelStyle:NSBezelStyleRounded];
    [self.diagnoseButton setTitle:NSLocalizedString(@"diag.button.check_status", nil)];
    [self.diagnoseButton setTarget:self];
    [self.diagnoseButton setAction:@selector(diagnoseButtonClicked:)];
    [self.view addSubview:self.diagnoseButton];
}

- (NSTextField*)makeStatusLabelWithFont:(NSFont*)font frame:(NSRect)frame {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
    [label setStringValue:@""];
    [self.view addSubview:label];
    return label;
}

- (void)startStatusTimer {
    if (self.statusTimer != nil) {
        return;
    }
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(refreshStatusPanel)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopStatusTimer {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)refreshStatusPanel {
    ConnectionDiagnosticsSnapshot snap = ConnectionDiagnostics::Capture();

    NSString* ok = NSLocalizedString(@"diag.value.ok", nil);
    NSString* missing = NSLocalizedString(@"diag.value.missing", nil);
    NSString* running = NSLocalizedString(@"diag.value.running", nil);
    NSString* stopped = NSLocalizedString(@"diag.value.stopped", nil);
    NSString* connected = NSLocalizedString(@"diag.value.connected", nil);
    NSString* idle = NSLocalizedString(@"diag.value.idle", nil);

    self.statusAccessibilityLabel.stringValue =
        [NSString stringWithFormat:NSLocalizedString(@"diag.label.accessibility", nil),
                 snap.accessibilityGranted ? ok : missing];
    self.statusScreenLabel.stringValue =
        [NSString stringWithFormat:NSLocalizedString(@"diag.label.screen_record", nil),
                 snap.screenRecordingGranted ? ok : missing];
    self.statusAgentLabel.stringValue =
        [NSString stringWithFormat:NSLocalizedString(@"diag.label.agent", nil),
                 snap.agentRunning ? running : stopped];
    self.statusSessionLabel.stringValue =
        [NSString stringWithFormat:NSLocalizedString(@"diag.label.session", nil),
                 snap.rdpClientConnected ? connected : idle];

    if (snap.overallState == 1) {
        self.statusHintLabel.stringValue = NSLocalizedString(@"diag.hint.permissions", nil);
    } else if (snap.overallState == 3) {
        NSString* key = snap.lastStartErrorKey != NULL && snap.lastStartErrorKey[0] != '\0'
            ? [NSString stringWithUTF8String:snap.lastStartErrorKey]
            : @"diag.error.agent_start_failed";
        self.statusHintLabel.stringValue = NSLocalizedString(key, nil);
    } else if (snap.overallState == 2) {
        self.statusHintLabel.stringValue = NSLocalizedString(@"diag.hint.agent_stopped", nil);
    } else if (snap.rdpClientConnected) {
        self.statusHintLabel.stringValue = NSLocalizedString(@"diag.hint.connected", nil);
    } else {
        self.statusHintLabel.stringValue = NSLocalizedString(@"diag.hint.ready", nil);
    }

    if (snap.agentRunning) {
        [self setEnabledBtnStyle:self.startRemoteConnectionBtn];
    } else {
        [self setDisabledBtnStyle:self.startRemoteConnectionBtn];
    }
    // Tray refresh is owned by AppDelegate's timer only (avoid double Capture every 2s).
}

- (IBAction)openPermissionWindowBtnClicked:(id)sender {
    self.permSettingsWindow = [[PermissionSettingsWindow alloc] initWithWindowNibName:@"PermissionSettingsWindow"];

    NSWindow* settingsModalWindow = [self.permSettingsWindow window];
    NSWindow* host = self.view.window;
    if (host == nil || host.isVisible == NO) {
        [NSApp activateIgnoringOtherApps:YES];
        if (host != nil) {
            [host makeKeyAndOrderFront:nil];
            [host orderFrontRegardless];
        }
    }

    host = self.view.window;
    if (host == nil) {
        // Fallback: present as a free-standing window if no host sheet parent.
        [settingsModalWindow center];
        [settingsModalWindow makeKeyAndOrderFront:nil];
        return;
    }

    [host beginSheet:settingsModalWindow completionHandler:^(NSModalResponse returnCode) {
        (void)returnCode;
        [self refreshStatusPanel];
    }];
}

- (IBAction)startRemoteConnectionBtnClicked:(id)sender {
    [self startRemoteConnectionServer:NO];
    [self refreshStatusPanel];
}

- (IBAction)diagnoseButtonClicked:(id)sender {
    ConnectionDiagnosticsSnapshot snap = ConnectionDiagnostics::Capture();
    NSMutableString* body = [NSMutableString string];
    [body appendFormat:@"• %@\n", self.statusAccessibilityLabel.stringValue];
    [body appendFormat:@"• %@\n", self.statusScreenLabel.stringValue];
    [body appendFormat:@"• %@\n", self.statusAgentLabel.stringValue];
    [body appendFormat:@"• %@\n\n", self.statusSessionLabel.stringValue];
    [body appendString:self.statusHintLabel.stringValue ?: @""];

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"diag.alert.title", nil)];
    [alert setInformativeText:body];
    if (snap.overallState == 1) {
        [alert addButtonWithTitle:NSLocalizedString(@"diag.button.open_permissions", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"permission.button.close", nil)];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [self openPermissionWindowBtnClicked:nil];
        }
        return;
    }
    [alert addButtonWithTitle:NSLocalizedString(@"permission.button.ok", nil)];
    [alert runModal];
    (void)sender;
}

- (void)startRemoteConnectionServer:(BOOL)silent {
    if (PermissionCheckUtils::HasAllPermissionToStartRemoteConnection() == false) {
        if (silent == NO) {
            [self openPermissionWindowBtnClicked:nil];
        }
        return;
    }

    bool didStart = StartRemoteConnectionServerService();
    if (didStart == true || IsRemoteConnectionServerServiceRunning() == true) {
        [self setEnabledBtnStyle:self.startRemoteConnectionBtn];
    } else if (silent == NO) {
        NSAlert* msg = [[NSAlert alloc] init];
        if (msg != nil) {
            [msg setMessageText:NSLocalizedString(@"main.alert.title", nil)];
            const char* key = ConnectionDiagnostics::LastStartErrorKey();
            NSString* text = (key != NULL && key[0] != '\0')
                ? NSLocalizedString([NSString stringWithUTF8String:key], nil)
                : NSLocalizedString(@"diag.error.agent_start_failed", nil);
            [msg setInformativeText:text];
            [msg runModal];
        }
    }
}

- (void)stopRemoteConnectionServer {
    StopRemoteConnectionServerService();
    [self setDisabledBtnStyle:self.startRemoteConnectionBtn];
    [self refreshStatusPanel];
}

- (IBAction)aboutUrlClicked:(id)sender {
    NSURL* url = [NSURL URLWithString:@"https://github.com/bho3538/osxrdp"];
    [[NSWorkspace sharedWorkspace] openURL:url];
    (void)sender;
}

- (IBAction)onStartupChanged:(id)sender {
    bool isSwitchOn = self.startupSwitch.state == NSControlStateValueOn;

    if (isSwitchOn) {
        StartupManager::EnableStartup();
    } else {
        StartupManager::DisableStartup();
    }
}

- (void)setDisabledBtnStyle:(NSButton*)btn {
    if (btn == nil) {
        return;
    }

    [btn setTitle:NSLocalizedString(@"main.button.stopped", nil)];
    [btn setBezelColor:[NSColor systemRedColor]];
}

- (void)setEnabledBtnStyle:(NSButton*)btn {
    if (btn == nil) {
        return;
    }

    [btn setTitle:NSLocalizedString(@"main.button.running", nil)];
    [btn setBezelColor:[NSColor systemGreenColor]];
}

@end
