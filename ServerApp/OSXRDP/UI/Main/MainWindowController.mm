#import "MainWindowController.h"

#import "MainViewController.h"

@interface MainWindowController ()

@property (strong) IBOutlet MainViewController* mainViewController;
@property (assign) BOOL didInitializeMainUI;

@end

@implementation MainWindowController

- (void)initializeMainUI {
    if (self.didInitializeMainUI == YES) {
        return;
    }

    self.didInitializeMainUI = YES;
    [self.window setContentSize:NSMakeSize(560.0, 450.0)];
    self.window.minSize = NSMakeSize(520.0, 420.0);
    self.window.title = @"OSXRDP";
    self.window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    [self.mainViewController configureInitialState];
}

- (void)showMainWindow {
    [self initializeMainUI];

    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

- (void)showPermissionSetup {
    [self showMainWindow];
    [self.mainViewController showPermissionSetup];
}

@end
