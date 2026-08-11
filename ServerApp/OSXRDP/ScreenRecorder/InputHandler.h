#ifndef InputHandler_hpp
#define InputHandler_hpp

#include "InputMapping.h"
#include "xstream.h"
#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <deque>
#include <memory>

class InputHandler {
public:
    InputHandler();
    ~InputHandler();
    
    void UpdateDisplayRes(int originalDisplayWidth, int originalDisplayHeight, int recordDisplayWidth, int recordDisplayHeight);
    void ResetDisplayLayout();
    bool AddDisplayLayout(int clientLeft, int clientTop, int clientWidth, int clientHeight, int displayOriginX, int displayOriginY, int displayWidth, int displayHeight, int displayId);
    
    void HandleMousseInputEvent(xstream_t* cmd);
    void HandleKeyboardInputEvent(xstream_t* cmd);
    
private:
    struct DISPLAY_LAYOUT {
        int clientLeft;
        int clientTop;
        int clientWidth;
        int clientHeight;
        int displayId;
        int displayOriginX;
        int displayOriginY;
        float scaleX;
        float scaleY;
    };

    int _originalDisplayWidth;
    int _originalDisplayHeight;
    int _recordDisplayWidth;
    int _recordDisplayHeight;

    struct DISPLAY_LAYOUT _displayLayouts[16];
    int _displayLayoutCnt;
    
    int _lastMousePosX;
    int _lastMousePosY;
    int _lastMouseClickPosX;
    int _lastMouseClickPosY;
    
    float _scaleX;
    float _scaleY;
    
    union MOUSE_DOWN_STATUS {
        struct STATUS {
            char leftKeyDown;
            char rightKeyDown;
            char wheelKeyDown;
            char backKeyDown;
            char forwardKeyDown;
            char dummy1;
            char dummy2;
            char dummy3;
        } downStatus;
        unsigned long status;
    } _mouseKeyStatus;
    
    int _mouseClickCnt;
    int _mouseEventNumber;
    int _leftMouseEventNumber;
    int _rightMouseEventNumber;
    int _wheelMouseEventNumber;
    int _backMouseEventNumber;
    int _forwardMouseEventNumber;
    int _lastMouseButton;
    long long _lastMouseClickTime;
    long long _lastMouseInputEventTime;

    struct WHEEL_STATE {
        long long lastEventTime;
        int eventBurstCount;
        int fastEventCount;
        int lastDirection;
        float smoothedAmount;
        bool isTrackpad;
    } _verticalWheelState, _horizontalWheelState;
    
    CGEventFlags _keyboardModifierFlags;
    InputMapping::KeyboardState _inputMappingState;
    
    CGEventSourceRef _eventRef;
    CGEventSourceRef _keyboardEventRef;
    dispatch_queue_t _keyboardQueue;

    struct KEYBOARD_EVENT {
        InputMapping::KeyAction action;
        bool keyDown;
        CGKeyCode keyCode;
        CGEventFlags additionalFlags;
    };
    std::deque<KEYBOARD_EVENT> _bufferedKeyboardEvents;
    struct KEYBOARD_LIFETIME {
        bool active;
    };
    std::shared_ptr<KEYBOARD_LIFETIME> _keyboardLifetime;
    bool _keyboardShuttingDown;
    bool _imeSwitchPending;
    uint64_t _imeSwitchGeneration;
    
    void HandleMouseDoubleClick(CGEventRef ev, bool mouseDown, int mouseX, int mouseY, int mouseButton);
    bool MapClientPointToDisplayPoint(int clientX, int clientY, int* outX, int* outY);
    int GetMouseWheelMoveAmount(int direction, WHEEL_STATE* state);
    void PostScrollEvent(int verticalAmount, int horizontalAmount, bool continuous);
    void PostTrackpadScrollEvent(int amount, bool horizontal);
    
    void RestorePreviousMouseKeydownEvent();
    
    static int CalcPos(int clientPos, float scale);
    
    static long long GetCurrentEventTime();
    
    enum ModifierStateChange {
        ModifierStateNotModifier,
        ModifierStateUnchanged,
        ModifierStateChanged
    };

    ModifierStateChange UpdateKeyboardModifierState(CGKeyCode key, bool isDown);
    void HandleQueuedKeyboardEvent(const KEYBOARD_EVENT& event);
    void PostQueuedKeyboardEvent(const KEYBOARD_EVENT& event);
    void PostMissionControlShortcut();
    void BeginIMESwitch();
    void CompleteIMESwitch(uint64_t generation, bool success, double elapsed);
    void FlushBufferedKeyboardEvents();
};

#endif /* InputHandler_hpp */
