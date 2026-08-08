#import "InsetCardView.h"

@interface InsetCardView ()

@property (assign) CGFloat cardCornerRadius;

@end

@implementation InsetCardView

- (instancetype)initWithContentView:(NSView *)contentView
                         edgeInsets:(NSEdgeInsets)edgeInsets
                        cornerRadius:(CGFloat)cornerRadius {
    self = [super initWithFrame:NSZeroRect];
    if (self == nil) {
        return nil;
    }

    self.cardCornerRadius = cornerRadius;
    self.wantsLayer = YES;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:contentView];
    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:edgeInsets.left],
        [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-edgeInsets.right],
        [contentView.topAnchor constraintEqualToAnchor:self.topAnchor constant:edgeInsets.top],
        [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-edgeInsets.bottom],
    ]];
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    self.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    self.layer.cornerRadius = self.cardCornerRadius;
    self.layer.masksToBounds = YES;
}

@end
