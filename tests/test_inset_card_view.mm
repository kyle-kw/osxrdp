#import <AppKit/AppKit.h>

#import "../ServerApp/OSXRDP/UI/InsetCardView.h"
#import "harness.h"

TEST_CASE(test_card_fitting_size_includes_content_insets)
{
    NSTextField *title = [NSTextField labelWithString:@"Needs Permissions"];
    NSTextField *detail = [NSTextField labelWithString:@"Grant Accessibility and Screen Recording access."];
    NSStackView *content = [NSStackView stackViewWithViews:@[title, detail]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 6.0;

    NSEdgeInsets insets = NSEdgeInsetsMake(14.0, 16.0, 14.0, 16.0);
    InsetCardView *card = [[InsetCardView alloc] initWithContentView:content
                                                        edgeInsets:insets
                                                      cornerRadius:12.0];

    NSSize contentSize = content.fittingSize;
    NSSize cardSize = card.fittingSize;

    EXPECT_TRUE(cardSize.height >= contentSize.height + 27.0);
    EXPECT_TRUE(cardSize.width >= contentSize.width + 31.0);
}

int main(void)
{
    @autoreleasepool {
        RUN_TEST(test_card_fitting_size_includes_content_insets);
    }

    return test_main_finish("test_inset_card_view");
}
