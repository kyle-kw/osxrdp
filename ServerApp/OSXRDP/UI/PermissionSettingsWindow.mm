#import "PermissionSettingsWindow.h"

#include "../Utils/ConnectionStatusCoordinator.h"
#include "../Utils/PermissionCheckUtils.h"
#import "InsetCardView.h"

@interface PermissionSettingsWindow ()

@property (strong) NSTextField *accessibilityStatusLabel;
@property (strong) NSTextField *screenRecordingStatusLabel;
@property (strong) NSImageView *accessibilityIconView;
@property (strong) NSImageView *screenRecordingIconView;
@property (strong) NSButton *accessibilityGrantButton;
@property (strong) NSButton *screenRecordingGrantButton;
@property (strong) NSButton *restartButton;

@end

@implementation PermissionSettingsWindow

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 320)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = NSLocalizedString(@"permission.window.title", nil);
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self == nil) {
        return nil;
    }

    [self buildUI];
    window.delegate = self;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(connectionStatusDidChange:)
                                                 name:OSXRDPConnectionStatusDidChangeNotification
                                               object:ConnectionStatusCoordinator.shared];
    [self refreshPermissionStatus];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    NSTextField *intro = [NSTextField wrappingLabelWithString:NSLocalizedString(@"permission.intro", nil)];
    intro.textColor = NSColor.secondaryLabelColor;
    intro.font = [NSFont systemFontOfSize:12.0];

    InsetCardView *accessibilityRow = [self permissionRowWithTitle:NSLocalizedString(@"permission.label.accessibility", nil)
                                                             detail:NSLocalizedString(@"permission.detail.accessibility", nil)
                                                           iconView:&_accessibilityIconView
                                                        statusLabel:&_accessibilityStatusLabel
                                                         grantButton:&_accessibilityGrantButton
                                                        grantAction:@selector(grantAccessibilityClicked:)
                                                      settingsAction:@selector(openAccessibilitySettingsClicked:)];
    InsetCardView *screenRow = [self permissionRowWithTitle:NSLocalizedString(@"permission.label.screen_record", nil)
                                                      detail:NSLocalizedString(@"permission.detail.screen_record", nil)
                                                    iconView:&_screenRecordingIconView
                                                 statusLabel:&_screenRecordingStatusLabel
                                                  grantButton:&_screenRecordingGrantButton
                                                 grantAction:@selector(grantScreenRecordingClicked:)
                                               settingsAction:@selector(openScreenRecordingSettingsClicked:)];

    self.restartButton = [NSButton buttonWithTitle:NSLocalizedString(@"permission.button.restart_app", nil)
                                             target:self
                                             action:@selector(restartAppClicked:)];
    self.restartButton.hidden = YES;
    NSButton *doneButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.button.done", nil)
                                             target:self
                                             action:@selector(doneClicked:)];
    doneButton.keyEquivalent = @"\r";
    NSView *spacer = [[NSView alloc] init];
    NSStackView *footer = [NSStackView stackViewWithViews:@[self.restartButton, spacer, doneButton]];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.alignment = NSLayoutAttributeCenterY;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *root = [NSStackView stackViewWithViews:@[intro, accessibilityRow, screenRow, footer]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12.0;
    [root setCustomSpacing:18.0 afterView:intro];
    [root setCustomSpacing:18.0 afterView:screenRow];
    [content addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:20.0],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18.0],
        [intro.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [accessibilityRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [screenRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [footer.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];
}

- (InsetCardView *)permissionRowWithTitle:(NSString *)title
                                    detail:(NSString *)detail
                                  iconView:(NSImageView * __strong *)iconView
                               statusLabel:(NSTextField * __strong *)statusLabel
                                grantButton:(NSButton * __strong *)grantButton
                               grantAction:(SEL)grantAction
                             settingsAction:(SEL)settingsAction {
    NSImageView *icon = [[NSImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:24.0],
        [icon.heightAnchor constraintEqualToConstant:24.0],
    ]];

    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSTextField *detailLabel = [NSTextField wrappingLabelWithString:detail];
    detailLabel.font = [NSFont systemFontOfSize:11.0];
    detailLabel.textColor = NSColor.secondaryLabelColor;
    detailLabel.maximumNumberOfLines = 2;
    NSTextField *status = [NSTextField labelWithString:@""];
    status.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    NSStackView *text = [NSStackView stackViewWithViews:@[titleLabel, detailLabel, status]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 2.0;

    NSButton *grant = [NSButton buttonWithTitle:NSLocalizedString(@"permission.button.grant", nil)
                                         target:self
                                         action:grantAction];
    NSButton *settings = [NSButton buttonWithTitle:NSLocalizedString(@"permission.button.open_settings", nil)
                                            target:self
                                            action:settingsAction];
    settings.bezelStyle = NSBezelStyleInline;
    NSStackView *actions = [NSStackView stackViewWithViews:@[grant, settings]];
    actions.orientation = NSUserInterfaceLayoutOrientationVertical;
    actions.alignment = NSLayoutAttributeTrailing;
    actions.spacing = 4.0;

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, text, actions]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12.0;
    [text setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    InsetCardView *card = [[InsetCardView alloc] initWithContentView:row
                                                         edgeInsets:NSEdgeInsetsMake(12.0, 14.0, 12.0, 14.0)
                                                        cornerRadius:10.0];

    *iconView = icon;
    *statusLabel = status;
    *grantButton = grant;
    return card;
}

- (void)refreshPermissionStatus {
    ConnectionDiagnosticsSnapshot snap = [ConnectionStatusCoordinator.shared currentSnapshot];
    [self updatePermissionGranted:snap.accessibilityGranted
                           status:self.accessibilityStatusLabel
                             icon:self.accessibilityIconView
                           button:self.accessibilityGrantButton];
    [self updatePermissionGranted:snap.screenRecordingGranted
                           status:self.screenRecordingStatusLabel
                             icon:self.screenRecordingIconView
                           button:self.screenRecordingGrantButton];
    self.restartButton.hidden = !(
        snap.accessibilityGranted && snap.screenRecordingGranted &&
        [ConnectionStatusCoordinator.shared currentState] == ConnectionState::Failed);
}

- (void)connectionStatusDidChange:(NSNotification *)notification {
    [self refreshPermissionStatus];
    (void)notification;
}

- (void)updatePermissionGranted:(BOOL)granted
                         status:(NSTextField *)status
                           icon:(NSImageView *)icon
                         button:(NSButton *)button {
    status.stringValue = granted
        ? NSLocalizedString(@"permission.value.granted", nil)
        : NSLocalizedString(@"permission.value.required", nil);
    status.textColor = granted ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    button.title = granted
        ? NSLocalizedString(@"permission.button.granted", nil)
        : NSLocalizedString(@"permission.button.grant", nil);
    button.enabled = !granted;
    NSString *symbol = granted ? @"checkmark.circle.fill" : @"exclamationmark.circle.fill";
    NSColor *color = granted ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    if (@available(macOS 12.0, *)) {
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    }
    icon.image = image;
}

- (IBAction)grantAccessibilityClicked:(id)sender {
    PermissionCheckUtils::ShowAccPermissionRequestDialog();
    [ConnectionStatusCoordinator.shared refreshNow];
    (void)sender;
}

- (IBAction)grantScreenRecordingClicked:(id)sender {
    PermissionCheckUtils::ShowScreenRecordPermissionRequestDialog();
    [ConnectionStatusCoordinator.shared refreshNow];
    (void)sender;
}

- (IBAction)openAccessibilitySettingsClicked:(id)sender {
    PermissionCheckUtils::OpenAccPermissionSettings();
    (void)sender;
}

- (IBAction)openScreenRecordingSettingsClicked:(id)sender {
    PermissionCheckUtils::OpenScreenRecordPermissionSettings();
    (void)sender;
}

- (IBAction)restartAppClicked:(id)sender {
    pid_t pid = getpid();
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSString *escapedPath = [bundlePath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *command = [NSString stringWithFormat:
        @"while kill -0 %d 2>/dev/null; do sleep 0.5; done; open -n '%@'", pid, escapedPath];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sh";
    task.arguments = @[@"-c", command];
    @try {
        [task launch];
        [NSApp terminate:nil];
    } @catch (NSException *exception) {
        NSLog(@"[PermissionSettingsWindow] Failed to relaunch: %@", exception);
    }
    (void)sender;
}

- (IBAction)doneClicked:(id)sender {
    NSWindow *window = self.window;
    if (window.sheetParent != nil) {
        [window.sheetParent endSheet:window returnCode:NSModalResponseOK];
    } else {
        [self close];
    }
    (void)sender;
}

@end
