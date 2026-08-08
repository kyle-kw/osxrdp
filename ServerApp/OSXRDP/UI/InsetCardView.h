#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface InsetCardView : NSView

- (instancetype)initWithContentView:(NSView *)contentView
                         edgeInsets:(NSEdgeInsets)edgeInsets
                        cornerRadius:(CGFloat)cornerRadius NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
