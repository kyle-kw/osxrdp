#import "MainViewController.h"

#include "../../RemoteConnection/RemoteConnectionService.h"
#include "../../Utils/ConnectionStatusCoordinator.h"

#import "../../AppDelegate.h"
#import "../InsetCardView.h"
#import "../PermissionSettingsWindow.h"

@interface MainViewController ()

@property (strong) PermissionSettingsWindow *permissionSettingsWindow;
@property (strong) NSImageView *heroIconView;
@property (strong) NSTextField *heroTitleLabel;
@property (strong) NSTextField *heroDetailLabel;
@property (strong) NSButton *primaryActionButton;
@property (strong) NSTextField *accessibilityValueLabel;
@property (strong) NSTextField *screenRecordingValueLabel;
@property (strong) NSTextField *agentValueLabel;
@property (strong) NSTextField *sessionValueLabel;
@property (strong) NSImageView *accessibilityIconView;
@property (strong) NSImageView *screenRecordingIconView;
@property (strong) NSImageView *agentIconView;
@property (strong) NSImageView *sessionIconView;
@property (strong) InsetCardView *fileCard;
@property (strong) NSTextField *fileCardTitleLabel;
@property (assign) BOOL didConfigureInitialState;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildDashboard];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(connectionStatusDidChange:)
                                                 name:OSXRDPConnectionStatusDidChangeNotification
                                               object:ConnectionStatusCoordinator.shared];
    [self refreshDashboard];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureInitialState {
    if (self.didConfigureInitialState) {
        return;
    }
    self.didConfigureInitialState = YES;
    [self refreshDashboard];
}

- (void)buildDashboard {
    for (NSView *subview in self.view.subviews.copy) {
        [subview removeFromSuperview];
    }

    self.view.wantsLayer = YES;

    NSTextField *appTitle = [NSTextField labelWithString:@"OSXRDP"];
    appTitle.font = [NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold];
    NSTextField *appSubtitle = [NSTextField labelWithString:NSLocalizedString(@"main.subtitle", nil)];
    appSubtitle.font = [NSFont systemFontOfSize:13.0];
    appSubtitle.textColor = NSColor.secondaryLabelColor;
    NSStackView *titleStack = [NSStackView stackViewWithViews:@[appTitle, appSubtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 3.0;

    NSButton *settingsButton = [NSButton buttonWithTitle:NSLocalizedString(@"main.button.settings", nil)
                                                 target:self
                                                 action:@selector(settingsButtonClicked:)];
    settingsButton.bezelStyle = NSBezelStyleTexturedRounded;
    NSImage *gearImage = [NSImage imageWithSystemSymbolName:@"gearshape"
                                  accessibilityDescription:NSLocalizedString(@"main.button.settings", nil)];
    if (gearImage != nil) {
        settingsButton.image = gearImage;
        settingsButton.imagePosition = NSImageLeading;
    }

    NSStackView *header = [NSStackView stackViewWithViews:@[titleStack, settingsButton]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.distribution = NSStackViewDistributionFill;
    [titleStack setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [settingsButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.heroIconView = [[NSImageView alloc] init];
    self.heroIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.heroIconView.widthAnchor constraintEqualToConstant:42.0],
        [self.heroIconView.heightAnchor constraintEqualToConstant:42.0],
    ]];

    self.heroTitleLabel = [NSTextField labelWithString:@""];
    self.heroTitleLabel.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
    self.heroDetailLabel = [NSTextField wrappingLabelWithString:@""];
    self.heroDetailLabel.font = [NSFont systemFontOfSize:12.0];
    self.heroDetailLabel.textColor = NSColor.secondaryLabelColor;
    self.heroDetailLabel.maximumNumberOfLines = 2;
    NSStackView *heroText = [NSStackView stackViewWithViews:@[self.heroTitleLabel, self.heroDetailLabel]];
    heroText.orientation = NSUserInterfaceLayoutOrientationVertical;
    heroText.alignment = NSLayoutAttributeLeading;
    heroText.spacing = 5.0;

    self.primaryActionButton = [NSButton buttonWithTitle:@""
                                                  target:self
                                                  action:@selector(primaryActionClicked:)];
    self.primaryActionButton.bezelStyle = NSBezelStyleRounded;
    self.primaryActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryActionButton.widthAnchor constraintGreaterThanOrEqualToConstant:128.0].active = YES;

    NSStackView *heroContent = [NSStackView stackViewWithViews:@[self.heroIconView, heroText, self.primaryActionButton]];
    heroContent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    heroContent.alignment = NSLayoutAttributeCenterY;
    heroContent.spacing = 14.0;
    [heroText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.primaryActionButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    InsetCardView *heroCard = [self cardWithContentView:heroContent];

    NSTextField *readinessTitle = [NSTextField labelWithString:NSLocalizedString(@"main.readiness.title", nil)];
    readinessTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];

    NSView *accessibilityRow = [self statusRowWithTitle:NSLocalizedString(@"main.status.accessibility", nil)
                                              iconView:&_accessibilityIconView
                                            valueLabel:&_accessibilityValueLabel];
    NSView *screenRow = [self statusRowWithTitle:NSLocalizedString(@"main.status.screen_recording", nil)
                                        iconView:&_screenRecordingIconView
                                      valueLabel:&_screenRecordingValueLabel];
    NSView *agentRow = [self statusRowWithTitle:NSLocalizedString(@"main.status.remote_agent", nil)
                                       iconView:&_agentIconView
                                     valueLabel:&_agentValueLabel];
    NSView *sessionRow = [self statusRowWithTitle:NSLocalizedString(@"main.status.rdp_session", nil)
                                         iconView:&_sessionIconView
                                       valueLabel:&_sessionValueLabel];
    NSStackView *readinessRows = [NSStackView stackViewWithViews:@[accessibilityRow, screenRow, agentRow, sessionRow]];
    readinessRows.orientation = NSUserInterfaceLayoutOrientationVertical;
    readinessRows.alignment = NSLayoutAttributeLeading;
    readinessRows.spacing = 10.0;
    for (NSView *row in readinessRows.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:readinessRows.widthAnchor].active = YES;
    }
    InsetCardView *readinessCard = [self cardWithContentView:readinessRows];

    NSImage *clipboardImage = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard"
                                        accessibilityDescription:NSLocalizedString(@"main.files.title", nil)];
    NSImageView *fileIcon = [[NSImageView alloc] init];
    fileIcon.image = clipboardImage ?: [NSImage imageNamed:NSImageNameMultipleDocuments];
    fileIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [fileIcon.widthAnchor constraintEqualToConstant:28.0],
        [fileIcon.heightAnchor constraintEqualToConstant:28.0],
    ]];
    self.fileCardTitleLabel = [NSTextField labelWithString:@""];
    self.fileCardTitleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSTextField *fileDetail = [NSTextField labelWithString:NSLocalizedString(@"main.files.detail", nil)];
    fileDetail.textColor = NSColor.secondaryLabelColor;
    fileDetail.font = [NSFont systemFontOfSize:11.0];
    NSStackView *fileText = [NSStackView stackViewWithViews:@[self.fileCardTitleLabel, fileDetail]];
    fileText.orientation = NSUserInterfaceLayoutOrientationVertical;
    fileText.alignment = NSLayoutAttributeLeading;
    fileText.spacing = 3.0;
    NSButton *downloadsButton = [NSButton buttonWithTitle:NSLocalizedString(@"main.files.downloads", nil)
                                                    target:self
                                                    action:@selector(saveToDownloadsClicked:)];
    NSButton *folderButton = [NSButton buttonWithTitle:NSLocalizedString(@"main.files.folder", nil)
                                                 target:self
                                                 action:@selector(saveToFolderClicked:)];
    NSStackView *fileActions = [NSStackView stackViewWithViews:@[downloadsButton, folderButton]];
    fileActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileActions.spacing = 6.0;
    NSStackView *fileContent = [NSStackView stackViewWithViews:@[fileIcon, fileText, fileActions]];
    fileContent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileContent.alignment = NSLayoutAttributeCenterY;
    fileContent.spacing = 12.0;
    [fileText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.fileCard = [self cardWithContentView:fileContent];
    self.fileCard.hidden = YES;

    NSTextField *footer = [NSTextField wrappingLabelWithString:NSLocalizedString(@"main.footer", nil)];
    footer.textColor = NSColor.secondaryLabelColor;
    footer.font = [NSFont systemFontOfSize:11.0];
    footer.alignment = NSTextAlignmentCenter;

    NSStackView *rootStack = [NSStackView stackViewWithViews:@[
        header, heroCard, readinessTitle, readinessCard, self.fileCard, footer
    ]];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = 14.0;
    [rootStack setCustomSpacing:20.0 afterView:header];
    [rootStack setCustomSpacing:10.0 afterView:readinessTitle];
    [self.view addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [rootStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
        [rootStack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22.0],
        [rootStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-20.0],
        [header.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [heroCard.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [readinessCard.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [self.fileCard.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [footer.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
    ]];
}

- (InsetCardView *)cardWithContentView:(NSView *)contentView {
    return [[InsetCardView alloc] initWithContentView:contentView
                                          edgeInsets:NSEdgeInsetsMake(14.0, 16.0, 14.0, 16.0)
                                         cornerRadius:12.0];
}

- (NSView *)statusRowWithTitle:(NSString *)title
                      iconView:(NSImageView * __strong *)iconView
                    valueLabel:(NSTextField * __strong *)valueLabel {
    NSImageView *icon = [[NSImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:18.0],
        [icon.heightAnchor constraintEqualToConstant:18.0],
    ]];
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:13.0];
    NSTextField *value = [NSTextField labelWithString:@""];
    value.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    value.alignment = NSTextAlignmentRight;

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, titleLabel, value]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10.0;
    [titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [value setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSLayoutConstraint *width = [row.widthAnchor constraintGreaterThanOrEqualToConstant:440.0];
    width.priority = NSLayoutPriorityDefaultLow;
    width.active = YES;
    *iconView = icon;
    *valueLabel = value;
    return row;
}

- (void)connectionStatusDidChange:(NSNotification *)notification {
    [self refreshDashboard];
    (void)notification;
}

- (void)refreshDashboard {
    ConnectionStatusCoordinator *coordinator = ConnectionStatusCoordinator.shared;
    ConnectionDiagnosticsSnapshot snap = [coordinator currentSnapshot];
    ConnectionState state = [coordinator currentState];

    NSString *title = @"";
    NSString *detail = @"";
    NSString *symbol = @"circle";
    NSColor *color = NSColor.secondaryLabelColor;
    switch (state) {
        case ConnectionState::NeedsPermissions:
            title = NSLocalizedString(@"main.state.permissions.title", nil);
            detail = NSLocalizedString(@"main.state.permissions.detail", nil);
            symbol = @"exclamationmark.triangle.fill";
            color = NSColor.systemOrangeColor;
            break;
        case ConnectionState::Starting:
            title = NSLocalizedString(@"main.state.starting.title", nil);
            detail = NSLocalizedString(@"main.state.starting.detail", nil);
            symbol = @"arrow.triangle.2.circlepath";
            color = NSColor.controlAccentColor;
            break;
        case ConnectionState::Ready:
            title = NSLocalizedString(@"main.state.ready.title", nil);
            detail = NSLocalizedString(@"main.state.ready.detail", nil);
            symbol = @"checkmark.circle.fill";
            color = NSColor.systemGreenColor;
            break;
        case ConnectionState::Connected:
            title = NSLocalizedString(@"main.state.connected.title", nil);
            if (snap.currentWidth > 0 && snap.currentHeight > 0) {
                detail = [NSString stringWithFormat:NSLocalizedString(@"main.state.connected.metrics", nil),
                          snap.currentWidth, snap.currentHeight,
                          snap.currentCodecBuf[0] != '\0' ? [NSString stringWithUTF8String:snap.currentCodecBuf] : @"—",
                          snap.currentFramerate];
            } else {
                detail = NSLocalizedString(@"main.state.connected.detail", nil);
            }
            symbol = @"display";
            color = NSColor.systemBlueColor;
            break;
        case ConnectionState::Stopped:
            title = NSLocalizedString(@"main.state.stopped.title", nil);
            detail = NSLocalizedString(@"main.state.stopped.detail", nil);
            symbol = @"pause.circle.fill";
            color = NSColor.secondaryLabelColor;
            break;
        case ConnectionState::Failed:
            title = NSLocalizedString(@"main.state.failed.title", nil);
            if (snap.lastStartErrorKey != NULL && snap.lastStartErrorKey[0] != '\0') {
                detail = NSLocalizedString([NSString stringWithUTF8String:snap.lastStartErrorKey], nil);
            } else {
                detail = NSLocalizedString(@"main.state.failed.detail", nil);
            }
            symbol = @"xmark.octagon.fill";
            color = NSColor.systemRedColor;
            break;
    }

    self.heroTitleLabel.stringValue = title;
    self.heroDetailLabel.stringValue = detail;
    [self setImageView:self.heroIconView symbol:symbol color:color];

    ConnectionPrimaryAction action = ConnectionPrimaryActionForState(state);
    self.primaryActionButton.enabled = action != ConnectionPrimaryAction::None;
    switch (action) {
        case ConnectionPrimaryAction::None:
            self.primaryActionButton.title = NSLocalizedString(@"main.action.starting", nil);
            break;
        case ConnectionPrimaryAction::SetUpPermissions:
            self.primaryActionButton.title = NSLocalizedString(@"main.action.permissions", nil);
            break;
        case ConnectionPrimaryAction::StartService:
            self.primaryActionButton.title = NSLocalizedString(@"main.action.start", nil);
            break;
        case ConnectionPrimaryAction::StopService:
            self.primaryActionButton.title = NSLocalizedString(@"main.action.stop", nil);
            break;
        case ConnectionPrimaryAction::Retry:
            self.primaryActionButton.title = NSLocalizedString(@"main.action.retry", nil);
            break;
    }

    [self updateStatusValue:self.accessibilityValueLabel
                   iconView:self.accessibilityIconView
                         ok:snap.accessibilityGranted
                    okTitle:NSLocalizedString(@"main.value.granted", nil)
               missingTitle:NSLocalizedString(@"main.value.required", nil)];
    [self updateStatusValue:self.screenRecordingValueLabel
                   iconView:self.screenRecordingIconView
                         ok:snap.screenRecordingGranted
                    okTitle:NSLocalizedString(@"main.value.granted", nil)
               missingTitle:NSLocalizedString(@"main.value.required", nil)];
    [self updateStatusValue:self.agentValueLabel
                   iconView:self.agentIconView
                         ok:snap.agentRunning
                    okTitle:NSLocalizedString(@"main.value.running", nil)
               missingTitle:NSLocalizedString(@"main.value.stopped", nil)];

    self.sessionValueLabel.stringValue = snap.rdpClientConnected
        ? NSLocalizedString(@"main.value.connected", nil)
        : NSLocalizedString(@"main.value.waiting", nil);
    [self setImageView:self.sessionIconView
                symbol:snap.rdpClientConnected ? @"checkmark.circle.fill" : @"circle"
                 color:snap.rdpClientConnected ? NSColor.systemBlueColor : NSColor.tertiaryLabelColor];

    self.fileCard.hidden = snap.remoteFileCount <= 0;
    if (snap.remoteFileCount > 0) {
        self.fileCardTitleLabel.stringValue =
            [NSString stringWithFormat:NSLocalizedString(@"main.files.count", nil), snap.remoteFileCount];
    }
}

- (void)updateStatusValue:(NSTextField *)label
                 iconView:(NSImageView *)iconView
                       ok:(BOOL)ok
                  okTitle:(NSString *)okTitle
             missingTitle:(NSString *)missingTitle {
    label.stringValue = ok ? okTitle : missingTitle;
    label.textColor = ok ? NSColor.labelColor : NSColor.systemOrangeColor;
    [self setImageView:iconView
                symbol:ok ? @"checkmark.circle.fill" : @"exclamationmark.circle.fill"
                 color:ok ? NSColor.systemGreenColor : NSColor.systemOrangeColor];
}

- (void)setImageView:(NSImageView *)imageView symbol:(NSString *)symbol color:(NSColor *)color {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    if (image == nil) {
        image = [NSImage imageNamed:NSImageNameStatusAvailable];
    }
    if (@available(macOS 12.0, *)) {
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    }
    imageView.image = image;
}

- (IBAction)primaryActionClicked:(id)sender {
    ConnectionStatusCoordinator *coordinator = ConnectionStatusCoordinator.shared;
    ConnectionState state = [coordinator currentState];
    switch (ConnectionPrimaryActionForState(state)) {
        case ConnectionPrimaryAction::SetUpPermissions:
            [self showPermissionSetup];
            break;
        case ConnectionPrimaryAction::StartService:
        case ConnectionPrimaryAction::Retry:
            [coordinator startService];
            break;
        case ConnectionPrimaryAction::StopService:
            if (state == ConnectionState::Connected && ![self confirmDisconnect]) {
                return;
            }
            [coordinator stopService];
            break;
        case ConnectionPrimaryAction::None:
            break;
    }
    (void)sender;
}

- (BOOL)confirmDisconnect {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"main.stop.confirm.title", nil);
    alert.informativeText = NSLocalizedString(@"main.stop.confirm.message", nil);
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:NSLocalizedString(@"common.cancel", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"main.action.stop", nil)];
    return [alert runModal] == NSAlertSecondButtonReturn;
}

- (void)showPermissionSetup {
    [NSApp activateIgnoringOtherApps:YES];
    [self.view.window makeKeyAndOrderFront:nil];

    if (self.permissionSettingsWindow != nil && self.permissionSettingsWindow.window.isVisible) {
        [self.permissionSettingsWindow.window makeKeyAndOrderFront:nil];
        return;
    }

    self.permissionSettingsWindow = [[PermissionSettingsWindow alloc] init];
    NSWindow *sheet = self.permissionSettingsWindow.window;
    __weak MainViewController *weakSelf = self;
    [self.view.window beginSheet:sheet completionHandler:^(NSModalResponse returnCode) {
        (void)returnCode;
        weakSelf.permissionSettingsWindow = nil;
        [ConnectionStatusCoordinator.shared refreshNow];
    }];
}

- (IBAction)settingsButtonClicked:(id)sender {
    AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
    [delegate showSettings];
    (void)sender;
}

- (IBAction)saveToDownloadsClicked:(id)sender {
    StartRemoteClipboardFileCopyToDownloads();
    (void)sender;
}

- (IBAction)saveToFolderClicked:(id)sender {
    StartRemoteClipboardFileCopy();
    (void)sender;
}

@end
