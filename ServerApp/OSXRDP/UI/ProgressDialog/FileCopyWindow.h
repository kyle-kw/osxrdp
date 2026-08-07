#import <Cocoa/Cocoa.h>

typedef void (^FileCopyCancelHandler)(void);

@interface FileCopyWindow : NSWindowController

@property (nonatomic, copy) FileCopyCancelHandler cancelHandler;

- (void)showWindow;
- (void)updateFileName:(NSString *)fileName
             itemIndex:(int)itemIndex
             itemTotal:(int)itemTotal
      transferredBytes:(unsigned long long)transferredBytes
            totalBytes:(unsigned long long)totalBytes;
- (void)closeWindow;

@end
