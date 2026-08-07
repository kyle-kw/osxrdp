#import "SettingsWindow.h"
#import "../../Utils/AppConfig.h"
#import "../../Utils/ConnectionDiagnostics.h"
#import "../../Utils/SessionMetrics.h"

@interface SettingsWindow ()

// Settings tab
@property (strong) NSButton *autoLandCheckbox;
@property (strong) NSButton *folderPickerBtn;
@property (strong) NSTextField *folderLabel;
@property (strong) NSStepper *framerateStepper;
@property (strong) NSTextField *framerateLabel;
@property (strong) NSPopUpButton *codecPopup;

// Diagnostics tab
@property (strong) NSTextField *diagResolutionLabel;
@property (strong) NSTextField *diagCodecLabel;
@property (strong) NSTextField *diagFramerateLabel;
@property (strong) NSTextField *diagFrameLagLabel;
@property (strong) NSTextField *diagFramesWrittenLabel;
@property (strong) NSTextField *diagDroppedFramesLabel;

@property (strong) NSTimer *diagTimer;
@property (strong) NSTabView *tabView;
// Guard against double endSheet (Done button + windowWillClose).
@property (assign) BOOL didEndSheet;

@end

@implementation SettingsWindow

- (void)loadWindow {
    NSRect frame = NSMakeRect(0, 0, 420, 380);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:styleMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    [window setTitle:NSLocalizedString(@"settings.window.title", nil)];
    self.window = window;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self buildUI];
    [self loadSettings];
    self.window.delegate = self;
    [self startDiagTimer];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self stopDiagTimer];
    (void)notification;
    // Title-bar close (not Done) must end the sheet so the host window is re-enabled.
    // Done already called endSheet; calling it again with Cancel would race the completionHandler.
    NSWindow *w = self.window;
    NSWindow *parent = (w != nil) ? w.sheetParent : nil;
    if (parent != nil && self.didEndSheet == NO) {
        self.didEndSheet = YES;
        [parent endSheet:w returnCode:NSModalResponseCancel];
    }
    if (self.onClose != nil) {
        void (^cb)(void) = self.onClose;
        self.onClose = nil;
        cb();
    }
}

- (void)dealloc {
    [self stopDiagTimer];
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;
    CGFloat width = content.bounds.size.width;

    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(10, 10, width - 20, content.bounds.size.height - 20)];
    [content addSubview:self.tabView];

    // Done button (bottom-right, outside tab view)
    NSButton *doneBtn = [[NSButton alloc] initWithFrame:NSMakeRect(width - 100, 10, 80, 28)];
    [doneBtn setBezelStyle:NSBezelStyleRounded];
    [doneBtn setTitle:NSLocalizedString(@"settings.button.done", nil)];
    [doneBtn setTarget:self];
    [doneBtn setAction:@selector(closeBtnClicked:)];
    [content addSubview:doneBtn];

    NSTabViewItem *settingsTab = [[NSTabViewItem alloc] initWithIdentifier:@"settings"];
    settingsTab.label = NSLocalizedString(@"settings.tab.settings", nil);
    settingsTab.view = [self buildSettingsTab];
    [self.tabView addTabViewItem:settingsTab];

    NSTabViewItem *diagTab = [[NSTabViewItem alloc] initWithIdentifier:@"diagnostics"];
    diagTab.label = NSLocalizedString(@"settings.tab.diagnostics", nil);
    diagTab.view = [self buildDiagnosticsTab];
    [self.tabView addTabViewItem:diagTab];
}

- (NSView *)buildSettingsTab {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 300)];
    CGFloat y = 260;

    // Auto-land checkbox
    self.autoLandCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 340, 24)];
    [self.autoLandCheckbox setButtonType:NSButtonTypeSwitch];
    [self.autoLandCheckbox setTitle:NSLocalizedString(@"settings.autoland.label", nil)];
    [self.autoLandCheckbox setTarget:self];
    [self.autoLandCheckbox setAction:@selector(autoLandChanged:)];
    [view addSubview:self.autoLandCheckbox];
    y -= 30;

    // Folder picker
    self.folderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 240, 24)];
    [self.folderLabel setEditable:NO];
    [self.folderLabel setBordered:NO];
    [self.folderLabel setDrawsBackground:NO];
    [self.folderLabel setStringValue:NSLocalizedString(@"settings.autoland.folder_default", nil)];
    [view addSubview:self.folderLabel];
    y -= 28;

    self.folderPickerBtn = [[NSButton alloc] initWithFrame:NSMakeRect(40, y, 160, 28)];
    [self.folderPickerBtn setBezelStyle:NSBezelStyleRounded];
    [self.folderPickerBtn setTitle:NSLocalizedString(@"settings.autoland.choose_folder", nil)];
    [self.folderPickerBtn setTarget:self];
    [self.folderPickerBtn setAction:@selector(folderPickerClicked:)];
    [view addSubview:self.folderPickerBtn];
    y -= 40;

    // Framerate stepper
    self.framerateLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    [self.framerateLabel setEditable:NO];
    [self.framerateLabel setBordered:NO];
    [self.framerateLabel setDrawsBackground:NO];
    [self.framerateLabel setStringValue:NSLocalizedString(@"settings.framerate.label", nil)];
    [view addSubview:self.framerateLabel];

    NSTextField *fpsValue = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 60, 24)];
    [fpsValue setTag:100];
    [fpsValue setEditable:NO];
    [view addSubview:fpsValue];

    self.framerateStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(195, y, 20, 24)];
    [self.framerateStepper setMinValue:0];
    [self.framerateStepper setMaxValue:120];
    [self.framerateStepper setIncrement:5];
    [self.framerateStepper setValueWraps:NO];
    [self.framerateStepper setTarget:self];
    [self.framerateStepper setAction:@selector(framerateChanged:)];
    [self.framerateStepper setEnabled:NO]; // Not wired to recorder yet
    [view addSubview:self.framerateStepper];
    y -= 24;

    NSTextField *framerateHint = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 220, 18)];
    [framerateHint setEditable:NO];
    [framerateHint setBordered:NO];
    [framerateHint setDrawsBackground:NO];
    [framerateHint setFont:[NSFont systemFontOfSize:11]];
    [framerateHint setTextColor:[NSColor secondaryLabelColor]];
    [framerateHint setStringValue:NSLocalizedString(@"settings.coming_soon", nil)];
    [view addSubview:framerateHint];
    y -= 30;

    // Codec popup
    NSTextField *codecLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    [codecLabel setEditable:NO];
    [codecLabel setBordered:NO];
    [codecLabel setDrawsBackground:NO];
    [codecLabel setStringValue:NSLocalizedString(@"settings.codec.label", nil)];
    [view addSubview:codecLabel];

    self.codecPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, y, 160, 26)];
    [self.codecPopup addItemWithTitle:NSLocalizedString(@"settings.codec.auto", nil)];
    [self.codecPopup addItemWithTitle:@"H.264"];
    [self.codecPopup addItemWithTitle:@"RFX"];
    [self.codecPopup addItemWithTitle:@"Bitmap"];
    [self.codecPopup setTarget:self];
    [self.codecPopup setAction:@selector(codecChanged:)];
    [self.codecPopup setEnabled:NO]; // Not wired to module yet
    [view addSubview:self.codecPopup];
    y -= 24;

    NSTextField *codecHint = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 220, 18)];
    [codecHint setEditable:NO];
    [codecHint setBordered:NO];
    [codecHint setDrawsBackground:NO];
    [codecHint setFont:[NSFont systemFontOfSize:11]];
    [codecHint setTextColor:[NSColor secondaryLabelColor]];
    [codecHint setStringValue:NSLocalizedString(@"settings.coming_soon", nil)];
    [view addSubview:codecHint];

    return view;
}

- (NSView *)buildDiagnosticsTab {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 300)];
    CGFloat y = 270;
    CGFloat labelWidth = 160;
    CGFloat valueWidth = 200;

    self.diagResolutionLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.resolution", nil) labelWidth:labelWidth valueWidth:valueWidth];
    self.diagCodecLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.codec", nil) labelWidth:labelWidth valueWidth:valueWidth];
    self.diagFramerateLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.framerate", nil) labelWidth:labelWidth valueWidth:valueWidth];
    self.diagFrameLagLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.frame_lag", nil) labelWidth:labelWidth valueWidth:valueWidth];
    self.diagFramesWrittenLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.frames_written", nil) labelWidth:labelWidth valueWidth:valueWidth];
    self.diagDroppedFramesLabel = [self makeDiagRowInView:view y:&y label:NSLocalizedString(@"settings.diag.dropped_frames", nil) labelWidth:labelWidth valueWidth:valueWidth];

    return view;
}

- (NSTextField *)makeDiagRowInView:(NSView *)view y:(CGFloat *)y label:(NSString *)label labelWidth:(CGFloat)labelWidth valueWidth:(CGFloat)valueWidth {
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(20, *y, labelWidth, 20)];
    [lbl setEditable:NO];
    [lbl setBordered:NO];
    [lbl setDrawsBackground:NO];
    [lbl setStringValue:label];
    [view addSubview:lbl];

    NSTextField *val = [[NSTextField alloc] initWithFrame:NSMakeRect(20 + labelWidth + 10, *y, valueWidth, 20)];
    [val setEditable:NO];
    [val setBordered:NO];
    [val setDrawsBackground:NO];
    [val setStringValue:@"-"];
    [view addSubview:val];
    *y -= 28;
    return val;
}

#pragma mark - Load/Save Settings

- (void)loadSettings {
    AppConfig *cfg = AppConfig.shared;

    [self.autoLandCheckbox setState:cfg.autoLandFiles ? NSControlStateValueOn : NSControlStateValueOff];
    [self updateFolderLabel];

    int fps = cfg.maxFramerate;
    NSTextField *fpsField = [self.window.contentView viewWithTag:100];
    [fpsField setStringValue:[NSString stringWithFormat:@"%d", fps]];
    [self.framerateStepper setIntValue:fps];

    NSString *codec = cfg.preferredCodec;
    if ([codec isEqualToString:@"h264"]) {
        [self.codecPopup selectItemAtIndex:1];
    } else if ([codec isEqualToString:@"rfx"]) {
        [self.codecPopup selectItemAtIndex:2];
    } else if ([codec isEqualToString:@"bitmap"]) {
        [self.codecPopup selectItemAtIndex:3];
    } else {
        [self.codecPopup selectItemAtIndex:0];
    }
}

- (void)updateFolderLabel {
    NSURL *url = AppConfig.shared.resolvedAutoLandFolderURL;
    if (url != nil) {
        self.folderLabel.stringValue = url.lastPathComponent ?: url.path;
    } else {
        self.folderLabel.stringValue = NSLocalizedString(@"settings.autoland.folder_default", nil);
    }
}

#pragma mark - Actions

- (void)autoLandChanged:(id)sender {
    AppConfig.shared.autoLandFiles = (self.autoLandCheckbox.state == NSControlStateValueOn);
}

- (void)folderPickerClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:NSLocalizedString(@"settings.autoland.choose_folder", nil)];

    if ([panel runModal] == NSModalResponseOK && panel.URL != nil) {
        NSError *error = nil;
        // Security-scoped so auto-land still works if the app is sandboxed later.
        NSData *bookmark = [panel.URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                                       includingResourceValuesForKeys:nil
                                                        relativeToURL:nil
                                                                error:&error];
        if (bookmark == nil) {
            // Non-sandbox / older path fallback
            bookmark = [panel.URL bookmarkDataWithOptions:0
                            includingResourceValuesForKeys:nil
                                             relativeToURL:nil
                                                     error:&error];
        }
        if (bookmark != nil) {
            AppConfig.shared.autoLandFolderBookmark = bookmark;
            [self updateFolderLabel];
        } else {
            NSLog(@"[SettingsWindow] bookmark creation failed: %@", error);
        }
    }
}

- (void)framerateChanged:(id)sender {
    int fps = (int)[self.framerateStepper intValue];
    NSTextField *fpsField = [self.window.contentView viewWithTag:100];
    [fpsField setIntValue:fps];
    AppConfig.shared.maxFramerate = fps;
}

- (void)codecChanged:(id)sender {
    NSInteger idx = [self.codecPopup indexOfSelectedItem];
    NSString *codec = @"";
    switch (idx) {
        case 1: codec = @"h264"; break;
        case 2: codec = @"rfx"; break;
        case 3: codec = @"bitmap"; break;
        default: codec = @""; break;
    }
    AppConfig.shared.preferredCodec = codec;
}

#pragma mark - Diagnostics Timer

- (void)startDiagTimer {
    self.diagTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(refreshDiagnostics)
                                                    userInfo:nil
                                                     repeats:YES];
    [self refreshDiagnostics];
}

- (void)stopDiagTimer {
    [self.diagTimer invalidate];
    self.diagTimer = nil;
}

- (void)refreshDiagnostics {
    ConnectionDiagnosticsSnapshot snap = ConnectionDiagnostics::Capture();

    self.diagResolutionLabel.stringValue =
        [NSString stringWithFormat:@"%dx%d", snap.currentWidth, snap.currentHeight];
    self.diagCodecLabel.stringValue =
        snap.currentCodec ? [NSString stringWithUTF8String:snap.currentCodec] : @"-";
    self.diagFramerateLabel.stringValue =
        [NSString stringWithFormat:@"%d fps", snap.currentFramerate];
    self.diagFrameLagLabel.stringValue =
        [NSString stringWithFormat:@"%d %@", snap.frameLag, NSLocalizedString(@"settings.diag.slots_pending", nil)];
    self.diagFramesWrittenLabel.stringValue =
        [NSString stringWithFormat:@"%llu", snap.totalFramesWritten];
    self.diagDroppedFramesLabel.stringValue =
        [NSString stringWithFormat:@"%llu", snap.droppedFrames];
}
- (IBAction)closeBtnClicked:(id)sender {
    NSWindow *w = self.window;
    if (w != nil && w.sheetParent != nil) {
        if (self.didEndSheet == NO) {
            self.didEndSheet = YES;
            [w.sheetParent endSheet:w returnCode:NSModalResponseOK];
        }
    } else {
        [self close];
    }
}

@end
