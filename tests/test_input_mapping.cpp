#include "harness.h"
#include "../ServerApp/OSXRDP/ScreenRecorder/InputMapping.h"
#include "../ScreenMirrorLib/osxrdp/packet.h"

#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

using InputMapping::KeyAction;
using InputMapping::KeyEvent;
using InputMapping::KeyboardState;
using InputMapping::ScrollAxis;
using InputMapping::ScrollEvent;

static void expect_key(const KeyEvent& event, KeyAction action,
                       int keyCode, uint64_t additionalFlags, bool keyDown) {
    EXPECT_EQ_INT(action, event.action);
    EXPECT_EQ_INT(keyCode, event.keyCode);
    EXPECT_TRUE(additionalFlags == event.additionalFlags);
    EXPECT_EQ_INT(keyDown, event.keyDown);
}

TEST_CASE(mac_style_maps_windows_and_alt_keys_by_side) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x5B, true, true),
               KeyAction::PostKey, kVK_Option, 0, true);
    expect_key(state.Translate(false, 0x5B, true, true),
               KeyAction::PostKey, kVK_Option, 0, false);
    expect_key(state.Translate(true, 0x5C, true, true),
               KeyAction::PostKey, kVK_RightOption, 0, true);
    expect_key(state.Translate(false, 0x5C, true, true),
               KeyAction::PostKey, kVK_RightOption, 0, false);
    expect_key(state.Translate(true, 0x38, false, true),
               KeyAction::PostKey, kVK_Command, 0, true);
    expect_key(state.Translate(false, 0x38, false, true),
               KeyAction::PostKey, kVK_Command, 0, false);
    expect_key(state.Translate(true, 0x38, true, true),
               KeyAction::PostKey, kVK_RightCommand, 0, true);
    expect_key(state.Translate(false, 0x38, true, true),
               KeyAction::PostKey, kVK_RightCommand, 0, false);
}

TEST_CASE(disabled_mode_preserves_existing_modifier_behavior) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x5B, true, false),
               KeyAction::PostKey, kVK_Command, 0, true);
    expect_key(state.Translate(false, 0x5B, true, false),
               KeyAction::PostKey, kVK_Command, 0, false);
    expect_key(state.Translate(true, 0x5C, true, false),
               KeyAction::PostKey, kVK_RightCommand, 0, true);
    expect_key(state.Translate(false, 0x5C, true, false),
               KeyAction::PostKey, kVK_RightCommand, 0, false);
    expect_key(state.Translate(true, 0x38, false, false),
               KeyAction::PostKey, kVK_Option, 0, true);
    expect_key(state.Translate(false, 0x38, false, false),
               KeyAction::PostKey, kVK_Option, 0, false);
    expect_key(state.Translate(true, 0x38, true, false),
               KeyAction::SwitchInputSource, kVK_RightOption, 0, true);
    expect_key(state.Translate(false, 0x38, true, false),
               KeyAction::SwitchInputSource, kVK_RightOption, 0, false);
    expect_key(state.Translate(true, 0x3A, false, false),
               KeyAction::PostKey, kVK_CapsLock, 0, true);
    expect_key(state.Translate(false, 0x3A, false, false),
               KeyAction::PostKey, kVK_CapsLock, 0, false);
    expect_key(state.Translate(true, 0x2A, false, false),
               KeyAction::PostKey, kVK_Shift, 0, true);
    expect_key(state.Translate(false, 0x2A, false, false),
               KeyAction::PostKey, kVK_Shift, 0, false);
    expect_key(state.Translate(true, 0x36, false, false),
               KeyAction::PostKey, kVK_RightShift, 0, true);
    expect_key(state.Translate(false, 0x36, false, false),
               KeyAction::PostKey, kVK_RightShift, 0, false);
}

TEST_CASE(mac_style_maps_capslock_to_input_source_and_shift_to_capslock) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x3A, false, true),
               KeyAction::SwitchInputSource, kVK_CapsLock, 0, true);
    expect_key(state.Translate(false, 0x3A, false, true),
               KeyAction::SwitchInputSource, kVK_CapsLock, 0, false);
    expect_key(state.Translate(true, 0x2A, false, true),
               KeyAction::ToggleCapsLockState, 0, 0, true);
    expect_key(state.Translate(false, 0x2A, false, true),
               KeyAction::ToggleCapsLockState, 0, 0, false);
    expect_key(state.Translate(true, 0x36, false, true),
               KeyAction::ToggleCapsLockState, 0, 0, true);
    expect_key(state.Translate(false, 0x36, false, true),
               KeyAction::ToggleCapsLockState, 0, 0, false);
}

TEST_CASE(controls_use_native_sided_keys) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x1D, false, true),
               KeyAction::PostKey, kVK_Control, 0, true);
    expect_key(state.Translate(false, 0x1D, false, true),
               KeyAction::PostKey, kVK_Control, 0, false);
    expect_key(state.Translate(true, 0x1D, true, true),
               KeyAction::PostKey, kVK_RightControl, 0, true);
    expect_key(state.Translate(false, 0x1D, true, true),
               KeyAction::PostKey, kVK_RightControl, 0, false);
}

TEST_CASE(home_and_end_add_command_without_persistent_modifier_state) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x47, true, true),
               KeyAction::PostKey, kVK_LeftArrow, kCGEventFlagMaskCommand, true);
    expect_key(state.Translate(false, 0x47, true, true),
               KeyAction::PostKey, kVK_LeftArrow, kCGEventFlagMaskCommand, false);
    expect_key(state.Translate(true, 0x4F, true, true),
               KeyAction::PostKey, kVK_RightArrow, kCGEventFlagMaskCommand, true);
    expect_key(state.Translate(false, 0x4F, true, true),
               KeyAction::PostKey, kVK_RightArrow, kCGEventFlagMaskCommand, false);

    expect_key(state.Translate(true, 0x47, true, false),
               KeyAction::PostKey, kVK_Home, 0, true);
    expect_key(state.Translate(false, 0x47, true, false),
               KeyAction::PostKey, kVK_Home, 0, false);
    expect_key(state.Translate(true, 0x4F, true, false),
               KeyAction::PostKey, kVK_End, 0, true);
    expect_key(state.Translate(false, 0x4F, true, false),
               KeyAction::PostKey, kVK_End, 0, false);
}

static void verify_windows_tab_chord(int windowsScanCode, int optionKeyCode) {
    KeyboardState state;

    expect_key(state.Translate(true, windowsScanCode, true, true),
               KeyAction::PostKey, optionKeyCode, 0, true);
    expect_key(state.Translate(true, 0x0F, false, true),
               KeyAction::MissionControl, 0, 0, true);
    expect_key(state.Translate(true, 0x0F, false, true),
               KeyAction::Ignore, 0, 0, true);
    expect_key(state.Translate(false, 0x0F, false, true),
               KeyAction::Ignore, 0, 0, false);
    expect_key(state.Translate(false, windowsScanCode, true, true),
               KeyAction::PostKey, optionKeyCode, 0, false);
}

TEST_CASE(windows_tab_maps_to_one_mission_control_action) {
    verify_windows_tab_chord(0x5B, kVK_Option);
    verify_windows_tab_chord(0x5C, kVK_RightOption);
}

TEST_CASE(disabled_windows_tab_remains_a_normal_tab_chord) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x5B, true, false),
               KeyAction::PostKey, kVK_Command, 0, true);
    expect_key(state.Translate(true, 0x0F, false, false),
               KeyAction::PostKey, kVK_Tab, 0, true);
    expect_key(state.Translate(false, 0x0F, false, false),
               KeyAction::PostKey, kVK_Tab, 0, false);
    expect_key(state.Translate(false, 0x5B, true, false),
               KeyAction::PostKey, kVK_Command, 0, false);
}

TEST_CASE(held_key_uses_press_mapping_until_release) {
    KeyboardState state;

    expect_key(state.Translate(true, 0x38, false, true),
               KeyAction::PostKey, kVK_Command, 0, true);
    expect_key(state.Translate(false, 0x38, false, false),
               KeyAction::PostKey, kVK_Command, 0, false);
    expect_key(state.Translate(true, 0x38, false, false),
               KeyAction::PostKey, kVK_Option, 0, true);
    expect_key(state.Translate(false, 0x38, false, true),
               KeyAction::PostKey, kVK_Option, 0, false);
}

TEST_CASE(invalid_standard_scancodes_are_ignored_without_masking) {
    KeyboardState state;

    expect_key(state.Translate(true, -1, false, true),
               KeyAction::Ignore, 0, 0, true);
    expect_key(state.Translate(true, 0x81, false, true),
               KeyAction::Ignore, 0, 0, true);
}

TEST_CASE(scroll_mapping_reverses_only_vertical_axis) {
    ScrollEvent event;

    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_WHEELUP, false, &event));
    EXPECT_EQ_INT(ScrollAxis::Vertical, event.axis);
    EXPECT_EQ_INT(1, event.direction);
    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_WHEELDOWN, false, &event));
    EXPECT_EQ_INT(-1, event.direction);

    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_WHEELUP, true, &event));
    EXPECT_EQ_INT(ScrollAxis::Vertical, event.axis);
    EXPECT_EQ_INT(-1, event.direction);
    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_WHEELDOWN, true, &event));
    EXPECT_EQ_INT(1, event.direction);

    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_HWHEELLEFT, true, &event));
    EXPECT_EQ_INT(ScrollAxis::Horizontal, event.axis);
    EXPECT_EQ_INT(1, event.direction);
    EXPECT_TRUE(InputMapping::TranslateScrollEvent(XRDP_MOUSE_HWHEELRIGHT, true, &event));
    EXPECT_EQ_INT(ScrollAxis::Horizontal, event.axis);
    EXPECT_EQ_INT(-1, event.direction);
    EXPECT_TRUE(!InputMapping::TranslateScrollEvent(XRDP_MOUSE_MOVE, true, &event));
}

int main(void) {
    RUN_TEST(mac_style_maps_windows_and_alt_keys_by_side);
    RUN_TEST(disabled_mode_preserves_existing_modifier_behavior);
    RUN_TEST(mac_style_maps_capslock_to_input_source_and_shift_to_capslock);
    RUN_TEST(controls_use_native_sided_keys);
    RUN_TEST(home_and_end_add_command_without_persistent_modifier_state);
    RUN_TEST(windows_tab_maps_to_one_mission_control_action);
    RUN_TEST(disabled_windows_tab_remains_a_normal_tab_chord);
    RUN_TEST(held_key_uses_press_mapping_until_release);
    RUN_TEST(invalid_standard_scancodes_are_ignored_without_masking);
    RUN_TEST(scroll_mapping_reverses_only_vertical_axis);
    return test_main_finish("test_input_mapping");
}
