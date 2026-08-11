#ifndef InputMapping_h
#define InputMapping_h

#include <stdint.h>

namespace InputMapping {

enum class KeyAction {
    Ignore,
    PostKey,
    SwitchInputSource,
    MissionControl,
};

struct KeyEvent {
    KeyAction action;
    uint16_t keyCode;
    uint64_t additionalFlags;
    bool keyDown;
};

class KeyboardState {
public:
    KeyboardState();

    KeyEvent Translate(bool keyDown, int scanCode, bool extended, bool macStyleEnabled);

private:
    struct CachedKey {
        bool active;
        KeyAction action;
        uint16_t keyCode;
        uint64_t additionalFlags;
    };

    CachedKey _cachedKeys[2][128];
    bool _leftWindowsDown;
    bool _rightWindowsDown;
    bool _leftWindowsChordEnabled;
    bool _rightWindowsChordEnabled;
    bool _missionControlTabDown;
};

enum class ScrollAxis {
    Vertical,
    Horizontal,
};

struct ScrollEvent {
    ScrollAxis axis;
    int direction;
};

bool TranslateScrollEvent(int inputType, bool macStyleEnabled, ScrollEvent* eventOut);

} // namespace InputMapping

#endif /* InputMapping_h */
