#import "SettingsWindow.h"

#include "../../Startup/StartupManager.h"
#include "../../Utils/ConnectionStatusCoordinator.h"
#import "../../Utils/AppConfig.h"
#import "../InsetCardView.h"

@interface SettingsWindow ()

@property (strong) NSSwitch *startupSwitch;
@property (strong) NSTextField *startupStatusLabel;
@property (strong) NSButton *startupSettingsButton;
@property (strong) NSSwitch *macNativeInputSwitch;
@property (strong) NSSwitch *autoLandSwitch;
@property (strong) NSTextField *folderLabel;
@property (strong) NSButton *folderPickerButton;
@property (strong) NSTextField *diagResolutionLabel;
@property (strong) NSTextField *diagCodecLabel;
@property (strong) NSTextField *diagFramerateLabel;
@property (strong) NSTextField *diagFrameLagLabel;
@property (strong) NSTextField *diagFramesWrittenLabel;
@property (strong) NSTextField *diagDroppedFramesLabel;
@property (strong) NSTextField *diagCopyFailuresLabel;
@property (strong) NSTextField *diagRFXFullRedrawLabel;
@property (strong) NSTextField *diagIMETimeoutsLabel;
@property (assign) BOOL didEndSheet;

@end

@implementation SettingsWindow

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 460)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = NSLocalizedString(@"settings.window.title", nil);
    window.minSize = NSMakeSize(500.0, 430.0);
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self == nil) {
        return nil;
    }

    window.delegate = self;
    [self buildUI];
    [self loadSettings];
    [self refreshDiagnostics];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(connectionStatusDidChange:)
                                                 name:OSXRDPConnectionStatusDidChangeNotification
                                               object:ConnectionStatusCoordinator.shared];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *window = self.window;
    if (window.sheetParent != nil && !self.didEndSheet) {
        self.didEndSheet = YES;
        [window.sheetParent endSheet:window returnCode:NSModalResponseCancel];
    }
    if (self.onClose != nil) {
        void (^callback)(void) = self.onClose;
        self.onClose = nil;
        callback();
    }
    (void)notification;
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSTabView *tabView = [[NSTabView alloc] init];
    tabView.translatesAutoresizingMaskIntoConstraints = NO;

    NSTabViewItem *generalItem = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    generalItem.label = NSLocalizedString(@"settings.tab.general", nil);
    generalItem.view = [self buildGeneralView];
    [tabView addTabViewItem:generalItem];

    NSTabViewItem *diagnosticsItem = [[NSTabViewItem alloc] initWithIdentifier:@"diagnostics"];
    diagnosticsItem.label = NSLocalizedString(@"settings.tab.diagnostics", nil);
    diagnosticsItem.view = [self buildDiagnosticsView];
    [tabView addTabViewItem:diagnosticsItem];

    NSButton *doneButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.button.done", nil)
                                             target:self
                                             action:@selector(doneClicked:)];
    doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    doneButton.keyEquivalent = @"\r";

    [content addSubview:tabView];
    [content addSubview:doneButton];
    [NSLayoutConstraint activateConstraints:@[
        [tabView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14.0],
        [tabView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14.0],
        [tabView.topAnchor constraintEqualToAnchor:content.topAnchor constant:12.0],
        [tabView.bottomAnchor constraintEqualToAnchor:doneButton.topAnchor constant:-10.0],
        [doneButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [doneButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16.0],
    ]];
}

- (NSView *)buildGeneralView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 350)];

    NSTextField *startupTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.startup.title", nil)];
    startupTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSTextField *startupDetail = [NSTextField wrappingLabelWithString:NSLocalizedString(@"settings.startup.detail", nil)];
    startupDetail.font = [NSFont systemFontOfSize:11.0];
    startupDetail.textColor = NSColor.secondaryLabelColor;
    self.startupStatusLabel = [NSTextField labelWithString:@""];
    self.startupStatusLabel.font = [NSFont systemFontOfSize:11.0];
    self.startupSettingsButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.startup.open_settings", nil)
                                                     target:self
                                                     action:@selector(openLoginItemsSettingsClicked:)];
    self.startupSettingsButton.bezelStyle = NSBezelStyleInline;
    NSStackView *startupStatusRow = [NSStackView stackViewWithViews:@[self.startupStatusLabel, self.startupSettingsButton]];
    startupStatusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    startupStatusRow.spacing = 8.0;
    NSStackView *startupText = [NSStackView stackViewWithViews:@[startupTitle, startupDetail, startupStatusRow]];
    startupText.orientation = NSUserInterfaceLayoutOrientationVertical;
    startupText.alignment = NSLayoutAttributeLeading;
    startupText.spacing = 3.0;
    self.startupSwitch = [[NSSwitch alloc] init];
    self.startupSwitch.target = self;
    self.startupSwitch.action = @selector(startupChanged:);
    NSStackView *startupRow = [NSStackView stackViewWithViews:@[startupText, self.startupSwitch]];
    startupRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    startupRow.alignment = NSLayoutAttributeCenterY;
    [startupText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    InsetCardView *startupCard = [self cardWithContentView:startupRow];

    NSTextField *inputTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.input_mapping.title", nil)];
    inputTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSTextField *inputDetail = [NSTextField wrappingLabelWithString:NSLocalizedString(@"settings.input_mapping.detail", nil)];
    inputDetail.font = [NSFont systemFontOfSize:11.0];
    inputDetail.textColor = NSColor.secondaryLabelColor;
    NSStackView *inputText = [NSStackView stackViewWithViews:@[inputTitle, inputDetail]];
    inputText.orientation = NSUserInterfaceLayoutOrientationVertical;
    inputText.alignment = NSLayoutAttributeLeading;
    inputText.spacing = 3.0;
    self.macNativeInputSwitch = [[NSSwitch alloc] init];
    self.macNativeInputSwitch.target = self;
    self.macNativeInputSwitch.action = @selector(macNativeInputChanged:);
    NSStackView *inputRow = [NSStackView stackViewWithViews:@[inputText, self.macNativeInputSwitch]];
    inputRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    inputRow.alignment = NSLayoutAttributeCenterY;
    [inputText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    InsetCardView *inputCard = [self cardWithContentView:inputRow];

    NSTextField *clipboardTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.files.title", nil)];
    clipboardTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSTextField *clipboardDetail = [NSTextField wrappingLabelWithString:NSLocalizedString(@"settings.files.detail", nil)];
    clipboardDetail.font = [NSFont systemFontOfSize:11.0];
    clipboardDetail.textColor = NSColor.secondaryLabelColor;
    NSStackView *clipboardText = [NSStackView stackViewWithViews:@[clipboardTitle, clipboardDetail]];
    clipboardText.orientation = NSUserInterfaceLayoutOrientationVertical;
    clipboardText.alignment = NSLayoutAttributeLeading;
    clipboardText.spacing = 3.0;
    self.autoLandSwitch = [[NSSwitch alloc] init];
    self.autoLandSwitch.target = self;
    self.autoLandSwitch.action = @selector(autoLandChanged:);
    NSStackView *clipboardRow = [NSStackView stackViewWithViews:@[clipboardText, self.autoLandSwitch]];
    clipboardRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    clipboardRow.alignment = NSLayoutAttributeCenterY;
    [clipboardText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *destinationTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.files.destination", nil)];
    destinationTitle.font = [NSFont systemFontOfSize:12.0];
    self.folderLabel = [NSTextField labelWithString:@""];
    self.folderLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    self.folderLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.folderPickerButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.autoland.choose_folder", nil)
                                                  target:self
                                                  action:@selector(folderPickerClicked:)];
    NSStackView *destinationRow = [NSStackView stackViewWithViews:@[
        destinationTitle, self.folderLabel, self.folderPickerButton
    ]];
    destinationRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    destinationRow.alignment = NSLayoutAttributeCenterY;
    destinationRow.spacing = 8.0;
    [self.folderLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *fileStack = [NSStackView stackViewWithViews:@[clipboardRow, destinationRow]];
    fileStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    fileStack.alignment = NSLayoutAttributeLeading;
    fileStack.spacing = 16.0;
    [destinationRow.widthAnchor constraintEqualToAnchor:fileStack.widthAnchor].active = YES;
    InsetCardView *fileCard = [self cardWithContentView:fileStack];

    NSStackView *root = [NSStackView stackViewWithViews:@[startupCard, inputCard, fileCard]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14.0;
    [view addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:18.0],
        [root.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-18.0],
        [root.topAnchor constraintEqualToAnchor:view.topAnchor constant:18.0],
        [startupCard.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [inputCard.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [fileCard.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];
    return view;
}

- (NSView *)buildDiagnosticsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 350)];
    NSTextField *sessionTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.diag.session_title", nil)];
    sessionTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    NSGridView *sessionGrid = [self diagnosticGridWithRows:@[
        @[NSLocalizedString(@"settings.diag.resolution", nil), [self diagnosticValue:&_diagResolutionLabel]],
        @[NSLocalizedString(@"settings.diag.codec", nil), [self diagnosticValue:&_diagCodecLabel]],
        @[NSLocalizedString(@"settings.diag.framerate", nil), [self diagnosticValue:&_diagFramerateLabel]],
        @[NSLocalizedString(@"settings.diag.frame_lag", nil), [self diagnosticValue:&_diagFrameLagLabel]],
    ]];

    NSTextField *counterTitle = [NSTextField labelWithString:NSLocalizedString(@"settings.diag.counters_title", nil)];
    counterTitle.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    NSGridView *counterGrid = [self diagnosticGridWithRows:@[
        @[NSLocalizedString(@"settings.diag.frames_written", nil), [self diagnosticValue:&_diagFramesWrittenLabel]],
        @[NSLocalizedString(@"settings.diag.dropped_frames", nil), [self diagnosticValue:&_diagDroppedFramesLabel]],
        @[NSLocalizedString(@"settings.diag.copy_failures", nil), [self diagnosticValue:&_diagCopyFailuresLabel]],
        @[NSLocalizedString(@"settings.diag.rfx_full_redraw", nil), [self diagnosticValue:&_diagRFXFullRedrawLabel]],
        @[NSLocalizedString(@"settings.diag.ime_timeouts", nil), [self diagnosticValue:&_diagIMETimeoutsLabel]],
    ]];

    NSStackView *root = [NSStackView stackViewWithViews:@[sessionTitle, sessionGrid, counterTitle, counterGrid]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 8.0;
    [root setCustomSpacing:18.0 afterView:sessionGrid];
    [view addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24.0],
        [root.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24.0],
        [root.topAnchor constraintEqualToAnchor:view.topAnchor constant:18.0],
        [sessionGrid.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [counterGrid.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];
    return view;
}

- (InsetCardView *)cardWithContentView:(NSView *)contentView {
    return [[InsetCardView alloc] initWithContentView:contentView
                                          edgeInsets:NSEdgeInsetsMake(14.0, 16.0, 14.0, 16.0)
                                         cornerRadius:10.0];
}

- (NSTextField *)diagnosticValue:(NSTextField * __strong *)target {
    NSTextField *label = [NSTextField labelWithString:@"—"];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    *target = label;
    return label;
}

- (NSGridView *)diagnosticGridWithRows:(NSArray<NSArray *> *)rows {
    NSMutableArray *gridRows = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        NSTextField *title = [NSTextField labelWithString:row[0]];
        title.textColor = NSColor.secondaryLabelColor;
        title.font = [NSFont systemFontOfSize:12.0];
        [gridRows addObject:@[title, row[1]]];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:gridRows];
    grid.rowSpacing = 7.0;
    grid.columnSpacing = 18.0;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementTrailing;
    return grid;
}

- (void)loadSettings {
    self.macNativeInputSwitch.state = AppConfig.shared.macNativeInputMappingEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoLandSwitch.state = AppConfig.shared.autoLandFiles ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateFolderLabel];
    [self updateFileControls];
    [self refreshStartupStatus];
}

- (void)refreshStartupStatus {
    StartupStatus status = StartupManager::GetStatus();
    self.startupSettingsButton.hidden = status != StartupStatus::RequiresApproval;
    switch (status) {
        case StartupStatus::Unsupported:
            self.startupSwitch.state = NSControlStateValueOff;
            self.startupSwitch.enabled = NO;
            self.startupStatusLabel.stringValue = NSLocalizedString(@"settings.startup.unsupported", nil);
            self.startupStatusLabel.textColor = NSColor.secondaryLabelColor;
            break;
        case StartupStatus::Disabled:
            self.startupSwitch.state = NSControlStateValueOff;
            self.startupSwitch.enabled = YES;
            self.startupStatusLabel.stringValue = NSLocalizedString(@"settings.startup.disabled", nil);
            self.startupStatusLabel.textColor = NSColor.secondaryLabelColor;
            break;
        case StartupStatus::RequiresApproval:
            self.startupSwitch.state = NSControlStateValueOn;
            self.startupSwitch.enabled = YES;
            self.startupStatusLabel.stringValue = NSLocalizedString(@"settings.startup.requires_approval", nil);
            self.startupStatusLabel.textColor = NSColor.systemOrangeColor;
            break;
        case StartupStatus::Enabled:
            self.startupSwitch.state = NSControlStateValueOn;
            self.startupSwitch.enabled = YES;
            self.startupStatusLabel.stringValue = NSLocalizedString(@"settings.startup.enabled", nil);
            self.startupStatusLabel.textColor = NSColor.systemGreenColor;
            break;
    }
}

- (void)updateFolderLabel {
    NSURL *url = AppConfig.shared.resolvedAutoLandFolderURL;
    self.folderLabel.stringValue = url.lastPathComponent ?: url.path ?: NSLocalizedString(@"settings.autoland.folder_default", nil);
    self.folderLabel.toolTip = url.path;
}

- (void)updateFileControls {
    BOOL enabled = self.autoLandSwitch.state == NSControlStateValueOn;
    self.folderLabel.textColor = enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
    self.folderPickerButton.enabled = enabled;
}

- (IBAction)startupChanged:(id)sender {
    BOOL enabled = self.startupSwitch.state == NSControlStateValueOn;
    NSError *error = nil;
    if (!StartupManager::SetEnabled(enabled, &error)) {
        [self refreshStartupStatus];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"settings.startup.error.title", nil);
        alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"settings.startup.error.message", nil);
        [alert runModal];
        return;
    }

    [self refreshStartupStatus];
    if (StartupManager::GetStatus() == StartupStatus::RequiresApproval) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"settings.startup.approval.title", nil);
        alert.informativeText = NSLocalizedString(@"settings.startup.approval.message", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"settings.startup.open_settings", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"common.later", nil)];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            StartupManager::OpenLoginItemsSettings();
        }
    }
    (void)sender;
}

- (IBAction)openLoginItemsSettingsClicked:(id)sender {
    StartupManager::OpenLoginItemsSettings();
    (void)sender;
}

- (IBAction)macNativeInputChanged:(id)sender {
    AppConfig.shared.macNativeInputMappingEnabled =
        self.macNativeInputSwitch.state == NSControlStateValueOn;
    (void)sender;
}

- (IBAction)autoLandChanged:(id)sender {
    AppConfig.shared.autoLandFiles = self.autoLandSwitch.state == NSControlStateValueOn;
    [self updateFileControls];
    (void)sender;
}

- (IBAction)folderPickerClicked:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = NSLocalizedString(@"settings.autoland.choose_folder", nil);
    if ([panel runModal] == NSModalResponseOK && panel.URL != nil) {
        NSError *error = nil;
        NSData *bookmark = [panel.URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                               includingResourceValuesForKeys:nil
                                                relativeToURL:nil
                                                        error:&error];
        if (bookmark == nil) {
            bookmark = [panel.URL bookmarkDataWithOptions:0
                            includingResourceValuesForKeys:nil
                                             relativeToURL:nil
                                                     error:&error];
        }
        if (bookmark != nil) {
            AppConfig.shared.autoLandFolderBookmark = bookmark;
            [self updateFolderLabel];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedString(@"settings.folder.error.title", nil);
            alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"settings.folder.error.message", nil);
            [alert runModal];
        }
    }
    (void)sender;
}

- (void)connectionStatusDidChange:(NSNotification *)notification {
    [self refreshDiagnostics];
    (void)notification;
}

- (void)refreshDiagnostics {
    ConnectionDiagnosticsSnapshot snap = [ConnectionStatusCoordinator.shared currentSnapshot];
    BOOL connected = snap.rdpClientConnected;
    if (!connected) {
        for (NSTextField *label in @[
            self.diagResolutionLabel,
            self.diagCodecLabel,
            self.diagFramerateLabel,
            self.diagFrameLagLabel,
            self.diagFramesWrittenLabel,
            self.diagDroppedFramesLabel,
            self.diagCopyFailuresLabel,
            self.diagRFXFullRedrawLabel,
            self.diagIMETimeoutsLabel,
        ]) {
            label.stringValue = @"—";
        }
        return;
    }

    self.diagResolutionLabel.stringValue = snap.currentWidth > 0
        ? [NSString stringWithFormat:@"%d × %d", snap.currentWidth, snap.currentHeight]
        : @"—";
    self.diagCodecLabel.stringValue = snap.currentCodecBuf[0] != '\0'
        ? [NSString stringWithUTF8String:snap.currentCodecBuf]
        : @"—";
    self.diagFramerateLabel.stringValue = [NSString stringWithFormat:@"%d fps", snap.currentFramerate];
    self.diagFrameLagLabel.stringValue =
        [NSString stringWithFormat:@"%d %@", snap.frameLag, NSLocalizedString(@"settings.diag.slots_pending", nil)];
    self.diagFramesWrittenLabel.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)snap.totalFramesWritten];
    self.diagDroppedFramesLabel.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)snap.droppedFrames];
    self.diagCopyFailuresLabel.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)snap.copyFailures];
    self.diagRFXFullRedrawLabel.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)snap.rfxFullRedrawRequests];
    self.diagIMETimeoutsLabel.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)snap.imeTimeouts];
}

- (IBAction)doneClicked:(id)sender {
    NSWindow *window = self.window;
    if (window.sheetParent != nil) {
        if (!self.didEndSheet) {
            self.didEndSheet = YES;
            [window.sheetParent endSheet:window returnCode:NSModalResponseOK];
        }
    } else {
        [self close];
    }
    (void)sender;
}

@end
