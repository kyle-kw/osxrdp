#include "harness.h"
#include "../ServerApp/OSXRDP/ScreenRecorder/InputSourceSelection.h"

TEST_CASE(cjkv_source_switches_to_first_non_cjkv_source) {
    const bool sources[] = { false, true, true };

    EXPECT_EQ_INT(0, InputSourceSelectionTargetIndex(sources, 3, 1, 2));
    EXPECT_EQ_INT(0, InputSourceSelectionTargetIndex(sources, 3, 2, 1));
}

TEST_CASE(non_cjkv_source_switches_to_preferred_cjkv_source) {
    const bool sources[] = { false, true, true };

    EXPECT_EQ_INT(2, InputSourceSelectionTargetIndex(sources, 3, 0, 2));
}

TEST_CASE(non_cjkv_source_falls_back_to_first_cjkv_source) {
    const bool sources[] = { false, true, true };

    EXPECT_EQ_INT(1, InputSourceSelectionTargetIndex(sources, 3, 0, -1));
    EXPECT_EQ_INT(1, InputSourceSelectionTargetIndex(sources, 3, 0, 0));
}

TEST_CASE(unknown_current_source_selects_cjkv_source) {
    const bool sources[] = { false, true, true };

    EXPECT_EQ_INT(2, InputSourceSelectionTargetIndex(sources, 3, -1, 2));
}

TEST_CASE(missing_target_category_is_rejected) {
    const bool onlyEnglish[] = { false, false };
    const bool onlyCJKV[] = { true, true };

    EXPECT_EQ_INT(-1, InputSourceSelectionTargetIndex(NULL, 0, -1, -1));
    EXPECT_EQ_INT(-1, InputSourceSelectionTargetIndex(onlyEnglish, 2, 0, -1));
    EXPECT_EQ_INT(-1, InputSourceSelectionTargetIndex(onlyCJKV, 2, 0, 1));
}

int main(void) {
    RUN_TEST(cjkv_source_switches_to_first_non_cjkv_source);
    RUN_TEST(non_cjkv_source_switches_to_preferred_cjkv_source);
    RUN_TEST(non_cjkv_source_falls_back_to_first_cjkv_source);
    RUN_TEST(unknown_current_source_selects_cjkv_source);
    RUN_TEST(missing_target_category_is_rejected);
    return test_main_finish("test_input_source_selection");
}
