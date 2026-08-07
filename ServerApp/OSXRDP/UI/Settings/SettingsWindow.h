#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SettingsWindow : NSWindowController <NSWindowDelegate>

// Invoked from windowWillClose (sheet end or free-standing window).
@property (nonatomic, copy, nullable) void (^onClose)(void);

@end

NS_ASSUME_NONNULL_END
