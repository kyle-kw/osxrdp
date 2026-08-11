#include "InputMapping.h"

#include "osxrdp/packet.h"
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <string.h>

namespace InputMapping {
namespace {

static const uint16_t kInvalidKeyCode = 0xFF;

static const uint16_t kStandardKeymap[] = {
    /* 0x00 */ kVK_ANSI_A,                      // Placeholder (No key)
    /* 0x01 */ kVK_Escape,
    /* 0x02 */ kVK_ANSI_1,
    /* 0x03 */ kVK_ANSI_2,
    /* 0x04 */ kVK_ANSI_3,
    /* 0x05 */ kVK_ANSI_4,
    /* 0x06 */ kVK_ANSI_5,
    /* 0x07 */ kVK_ANSI_6,
    /* 0x08 */ kVK_ANSI_7,
    /* 0x09 */ kVK_ANSI_8,
    /* 0x0a */ kVK_ANSI_9,
    /* 0x0b */ kVK_ANSI_0,
    /* 0x0c */ kVK_ANSI_Minus,
    /* 0x0d */ kVK_ANSI_Equal,
    /* 0x0e */ kVK_Delete,
    /* 0x0f */ kVK_Tab,
    /* 0x10 */ kVK_ANSI_Q,
    /* 0x11 */ kVK_ANSI_W,
    /* 0x12 */ kVK_ANSI_E,
    /* 0x13 */ kVK_ANSI_R,
    /* 0x14 */ kVK_ANSI_T,
    /* 0x15 */ kVK_ANSI_Y,
    /* 0x16 */ kVK_ANSI_U,
    /* 0x17 */ kVK_ANSI_I,
    /* 0x18 */ kVK_ANSI_O,
    /* 0x19 */ kVK_ANSI_P,
    /* 0x1a */ kVK_ANSI_LeftBracket,
    /* 0x1b */ kVK_ANSI_RightBracket,
    /* 0x1c */ kVK_Return,
    /* 0x1d */ kVK_Control,
    /* 0x1e */ kVK_ANSI_A,
    /* 0x1f */ kVK_ANSI_S,
    /* 0x20 */ kVK_ANSI_D,
    /* 0x21 */ kVK_ANSI_F,
    /* 0x22 */ kVK_ANSI_G,
    /* 0x23 */ kVK_ANSI_H,
    /* 0x24 */ kVK_ANSI_J,
    /* 0x25 */ kVK_ANSI_K,
    /* 0x26 */ kVK_ANSI_L,
    /* 0x27 */ kVK_ANSI_Semicolon,
    /* 0x28 */ kVK_ANSI_Quote,
    /* 0x29 */ kVK_ANSI_Grave,
    /* 0x2a */ kVK_Shift,
    /* 0x2b */ kVK_ANSI_Backslash,
    /* 0x2c */ kVK_ANSI_Z,
    /* 0x2d */ kVK_ANSI_X,
    /* 0x2e */ kVK_ANSI_C,
    /* 0x2f */ kVK_ANSI_V,
    /* 0x30 */ kVK_ANSI_B,
    /* 0x31 */ kVK_ANSI_N,
    /* 0x32 */ kVK_ANSI_M,
    /* 0x33 */ kVK_ANSI_Comma,
    /* 0x34 */ kVK_ANSI_Period,
    /* 0x35 */ kVK_ANSI_Slash,
    /* 0x36 */ kVK_RightShift,
    /* 0x37 */ kVK_ANSI_KeypadMultiply,
    /* 0x38 */ kVK_Option,
    /* 0x39 */ kVK_Space,
    /* 0x3a */ kVK_CapsLock,
    /* 0x3b */ kVK_F1,
    /* 0x3c */ kVK_F2,
    /* 0x3d */ kVK_F3,
    /* 0x3e */ kVK_F4,
    /* 0x3f */ kVK_F5,
    /* 0x40 */ kVK_F6,
    /* 0x41 */ kVK_F7,
    /* 0x42 */ kVK_F8,
    /* 0x43 */ kVK_F9,
    /* 0x44 */ kVK_F10,
    /* 0x45 */ kVK_ANSI_KeypadClear,
    /* 0x46 */ kVK_F14,
    /* 0x47 */ kVK_ANSI_Keypad7,
    /* 0x48 */ kVK_ANSI_Keypad8,
    /* 0x49 */ kVK_ANSI_Keypad9,
    /* 0x4a */ kVK_ANSI_KeypadMinus,
    /* 0x4b */ kVK_ANSI_Keypad4,
    /* 0x4c */ kVK_ANSI_Keypad5,
    /* 0x4d */ kVK_ANSI_Keypad6,
    /* 0x4e */ kVK_ANSI_KeypadPlus,
    /* 0x4f */ kVK_ANSI_Keypad1,
    /* 0x50 */ kVK_ANSI_Keypad2,
    /* 0x51 */ kVK_ANSI_Keypad3,
    /* 0x52 */ kVK_ANSI_Keypad0,
    /* 0x53 */ kVK_ANSI_KeypadDecimal,
    /* 0x54 */ kVK_F13,
    /* 0x55 */ kInvalidKeyCode,
    /* 0x56 */ kInvalidKeyCode,
    /* 0x57 */ kVK_F11,
    /* 0x58 */ kVK_F12,
    /* 0x59 */ kVK_ANSI_KeypadEquals,
};

KeyEvent IgnoreEvent(bool keyDown) {
    return { KeyAction::Ignore, 0, 0, keyDown };
}

KeyEvent MakeKeyEvent(KeyAction action, uint16_t keyCode,
                      uint64_t additionalFlags, bool keyDown) {
    return { action, keyCode, additionalFlags, keyDown };
}

KeyEvent TranslateUncached(bool keyDown, int scanCode, bool extended,
                           bool macStyleEnabled) {
    if (scanCode < 0 || scanCode >= 128) {
        return IgnoreEvent(keyDown);
    }

    if (!extended) {
        if (scanCode >= (int)(sizeof(kStandardKeymap) / sizeof(kStandardKeymap[0]))) {
            return IgnoreEvent(keyDown);
        }

        uint16_t keyCode = kStandardKeymap[scanCode];
        if (keyCode == kInvalidKeyCode) {
            return IgnoreEvent(keyDown);
        }
        if (macStyleEnabled) {
            switch (scanCode) {
                case 0x2A: // Left Shift -> Caps Lock
                case 0x36: // Right Shift -> Caps Lock
                    keyCode = kVK_CapsLock;
                    break;
                case 0x38:
                    keyCode = kVK_Command; // Left Alt -> Left Command
                    break;
                case 0x3A: // Caps Lock -> input source switch
                    return MakeKeyEvent(KeyAction::SwitchInputSource,
                                        kVK_CapsLock, 0, keyDown);
                default:
                    break;
            }
        }
        return MakeKeyEvent(KeyAction::PostKey, keyCode, 0, keyDown);
    }

    switch (scanCode) {
        case 0x1C:
            return MakeKeyEvent(KeyAction::PostKey, kVK_ANSI_KeypadEnter, 0, keyDown);
        case 0x1D:
            return MakeKeyEvent(KeyAction::PostKey, kVK_RightControl, 0, keyDown);
        case 0x35:
            return MakeKeyEvent(KeyAction::PostKey, kVK_ANSI_KeypadDivide, 0, keyDown);
        case 0x37:
            return MakeKeyEvent(KeyAction::PostKey, kVK_F13, 0, keyDown);
        case 0x38:
            if (macStyleEnabled) {
                return MakeKeyEvent(KeyAction::PostKey, kVK_RightCommand, 0, keyDown);
            }
            return MakeKeyEvent(KeyAction::SwitchInputSource, kVK_RightOption, 0, keyDown);
        case 0x72:
            return MakeKeyEvent(KeyAction::SwitchInputSource, kVK_RightOption, 0, keyDown);
        case 0x47:
            if (macStyleEnabled) {
                return MakeKeyEvent(KeyAction::PostKey, kVK_LeftArrow,
                                    kCGEventFlagMaskCommand, keyDown);
            }
            return MakeKeyEvent(KeyAction::PostKey, kVK_Home, 0, keyDown);
        case 0x48:
            return MakeKeyEvent(KeyAction::PostKey, kVK_UpArrow, 0, keyDown);
        case 0x49:
            return MakeKeyEvent(KeyAction::PostKey, kVK_PageUp, 0, keyDown);
        case 0x4B:
            return MakeKeyEvent(KeyAction::PostKey, kVK_LeftArrow, 0, keyDown);
        case 0x4D:
            return MakeKeyEvent(KeyAction::PostKey, kVK_RightArrow, 0, keyDown);
        case 0x4F:
            if (macStyleEnabled) {
                return MakeKeyEvent(KeyAction::PostKey, kVK_RightArrow,
                                    kCGEventFlagMaskCommand, keyDown);
            }
            return MakeKeyEvent(KeyAction::PostKey, kVK_End, 0, keyDown);
        case 0x50:
            return MakeKeyEvent(KeyAction::PostKey, kVK_DownArrow, 0, keyDown);
        case 0x51:
            return MakeKeyEvent(KeyAction::PostKey, kVK_PageDown, 0, keyDown);
        case 0x52:
        case 0x53:
            return MakeKeyEvent(KeyAction::PostKey, kVK_ForwardDelete, 0, keyDown);
        case 0x5B:
            return MakeKeyEvent(KeyAction::PostKey,
                                macStyleEnabled ? kVK_Option : kVK_Command,
                                0, keyDown);
        case 0x5C:
            return MakeKeyEvent(KeyAction::PostKey,
                                macStyleEnabled ? kVK_RightOption : kVK_RightCommand,
                                0, keyDown);
        case 0x5D:
            return MakeKeyEvent(KeyAction::PostKey, kVK_F13, 0, keyDown);
        default:
            return IgnoreEvent(keyDown);
    }
}

bool IsWindowsKey(int scanCode, bool extended) {
    return extended && (scanCode == 0x5B || scanCode == 0x5C);
}

bool IsTabKey(int scanCode, bool extended) {
    return !extended && scanCode == 0x0F;
}

} // namespace

KeyboardState::KeyboardState() :
    _leftWindowsDown(false),
    _rightWindowsDown(false),
    _leftWindowsChordEnabled(false),
    _rightWindowsChordEnabled(false),
    _missionControlTabDown(false) {
    memset(_cachedKeys, 0, sizeof(_cachedKeys));
}

KeyEvent KeyboardState::Translate(bool keyDown, int scanCode, bool extended,
                                  bool macStyleEnabled) {
    if (scanCode < 0 || scanCode >= 128) {
        return IgnoreEvent(keyDown);
    }

    const int extendedIndex = extended ? 1 : 0;
    CachedKey& cached = _cachedKeys[extendedIndex][scanCode];

    if (keyDown) {
        bool firstKeyDown = !cached.active;
        if (firstKeyDown) {
            KeyEvent translated = TranslateUncached(true, scanCode, extended, macStyleEnabled);
            cached.active = true;
            cached.action = translated.action;
            cached.keyCode = translated.keyCode;
            cached.additionalFlags = translated.additionalFlags;
        }

        if (IsWindowsKey(scanCode, extended)) {
            bool* down = scanCode == 0x5B ? &_leftWindowsDown : &_rightWindowsDown;
            bool* chordEnabled = scanCode == 0x5B
                ? &_leftWindowsChordEnabled : &_rightWindowsChordEnabled;
            *down = true;
            if (firstKeyDown) {
                *chordEnabled = macStyleEnabled;
            }
        }

        bool windowsChordDown =
            (_leftWindowsDown && _leftWindowsChordEnabled) ||
            (_rightWindowsDown && _rightWindowsChordEnabled);
        if (IsTabKey(scanCode, extended) && windowsChordDown) {
            if (_missionControlTabDown) {
                return IgnoreEvent(true);
            }
            _missionControlTabDown = true;
            return MakeKeyEvent(KeyAction::MissionControl, 0, 0, true);
        }

        return MakeKeyEvent(cached.action, cached.keyCode,
                            cached.additionalFlags, true);
    }

    if (IsTabKey(scanCode, extended) && _missionControlTabDown) {
        _missionControlTabDown = false;
        cached.active = false;
        return IgnoreEvent(false);
    }

    KeyEvent translated = cached.active
        ? MakeKeyEvent(cached.action, cached.keyCode, cached.additionalFlags, false)
        : TranslateUncached(false, scanCode, extended, macStyleEnabled);
    cached.active = false;

    if (IsWindowsKey(scanCode, extended)) {
        if (scanCode == 0x5B) {
            _leftWindowsDown = false;
            _leftWindowsChordEnabled = false;
        }
        else {
            _rightWindowsDown = false;
            _rightWindowsChordEnabled = false;
        }
    }

    return translated;
}

bool TranslateScrollEvent(int inputType, bool macStyleEnabled, ScrollEvent* eventOut) {
    if (eventOut == nullptr) {
        return false;
    }

    switch (inputType) {
        case XRDP_MOUSE_WHEELUP:
            eventOut->axis = ScrollAxis::Vertical;
            eventOut->direction = macStyleEnabled ? -1 : 1;
            return true;
        case XRDP_MOUSE_WHEELDOWN:
            eventOut->axis = ScrollAxis::Vertical;
            eventOut->direction = macStyleEnabled ? 1 : -1;
            return true;
        case XRDP_MOUSE_HWHEELLEFT:
            eventOut->axis = ScrollAxis::Horizontal;
            eventOut->direction = 1;
            return true;
        case XRDP_MOUSE_HWHEELRIGHT:
            eventOut->axis = ScrollAxis::Horizontal;
            eventOut->direction = -1;
            return true;
        default:
            return false;
    }
}

} // namespace InputMapping
