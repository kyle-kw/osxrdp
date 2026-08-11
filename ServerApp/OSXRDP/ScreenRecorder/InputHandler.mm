#include "InputHandler.h"

#include "osxrdp/packet.h"
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <sys/time.h>
#include <Carbon/Carbon.h>
#include <string.h>
#include <limits.h>

#import "CJKHelper.h"
#import "../Utils/AppConfig.h"
#import "../Utils/SessionMetrics.h"

static const size_t kMaxBufferedKeyboardEvents = 128;

static const CGEventFlags kDeviceLeftControlFlag = 0x00000001;
static const CGEventFlags kDeviceLeftShiftFlag = 0x00000002;
static const CGEventFlags kDeviceRightShiftFlag = 0x00000004;
static const CGEventFlags kDeviceLeftCommandFlag = 0x00000008;
static const CGEventFlags kDeviceRightCommandFlag = 0x00000010;
static const CGEventFlags kDeviceLeftOptionFlag = 0x00000020;
static const CGEventFlags kDeviceRightOptionFlag = 0x00000040;
static const CGEventFlags kDeviceRightControlFlag = 0x00002000;

InputHandler::InputHandler() :
    _originalDisplayWidth(0),
    _originalDisplayHeight(0),
    _recordDisplayWidth(0),
    _recordDisplayHeight(0),
    _displayLayoutCnt(0),
    _scaleX(0.0f),
    _scaleY(0.0f),
    _lastMousePosX(0),
    _lastMousePosY(0),
    _lastMouseClickPosX(0),
    _lastMouseClickPosY(0),
    _eventRef(0),
    _keyboardModifierFlags(0),
    _mouseClickCnt(0),
    _mouseEventNumber(0),
    _leftMouseEventNumber(0),
    _rightMouseEventNumber(0),
    _wheelMouseEventNumber(0),
    _backMouseEventNumber(0),
    _forwardMouseEventNumber(0),
    _lastMouseButton(-1),
    _lastMouseClickTime(0),
    _lastMouseInputEventTime(0),
    _keyboardEventRef(0),
    _keyboardQueue(NULL),
    _keyboardShuttingDown(false)
{
    memset(_displayLayouts, 0x00, sizeof(_displayLayouts));
    memset(&_verticalWheelState, 0x00, sizeof(_verticalWheelState));
    memset(&_horizontalWheelState, 0x00, sizeof(_horizontalWheelState));
    _eventRef = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    _keyboardEventRef = [CJKHelper sharedKeyboardEventSource];
    if (_keyboardEventRef != NULL) CFRetain(_keyboardEventRef);
    _keyboardQueue = dispatch_queue_create("osxrdp.keyboard", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_keyboardQueue, this, this, NULL);
    _keyboardLifetime = std::make_shared<KEYBOARD_LIFETIME>();
    __atomic_store_n(&_keyboardLifetime->active, true, __ATOMIC_RELEASE);
    
    _mouseKeyStatus.status = 0;
}

InputHandler::~InputHandler() {
    __atomic_store_n(&_keyboardLifetime->active, false, __ATOMIC_RELEASE);
    auto shutdown = ^{
        _keyboardShuttingDown = true;
        _imeSwitchState.Cancel();
        _bufferedKeyboardEvents.clear();
    };
    if (_keyboardQueue != NULL) {
        if (dispatch_get_specific(this) == this) shutdown();
        else dispatch_sync(_keyboardQueue, shutdown);
    }
    // ARC owns dispatch_queue_t fields; draining above is required for lifetime,
    // but dispatch_release would over-release the queue.
    _keyboardQueue = NULL;
    if (_keyboardEventRef != 0) {
        CFRelease(_keyboardEventRef);
        _keyboardEventRef = 0;
    }
    if (_eventRef != 0) {
        CFRelease(_eventRef);
        _eventRef = 0;
    }
}

void InputHandler::UpdateDisplayRes(int originalDisplayWidth, int originalDisplayHeight, int recordDisplayWidth, int recordDisplayHeight) {
    if (recordDisplayWidth <= 0 || recordDisplayHeight <= 0) {
        return;
    }

    _originalDisplayWidth = originalDisplayWidth;
    _originalDisplayHeight = originalDisplayHeight;
    _recordDisplayWidth = recordDisplayWidth;
    _recordDisplayHeight = recordDisplayHeight;
    
    _scaleX = (float)_originalDisplayWidth / _recordDisplayWidth;
    _scaleY = (float)_originalDisplayHeight / _recordDisplayHeight;
    
    printf("UpdateDisplayResolution origin: %d %d , record: %d %d , scale: %f %f\n", _originalDisplayWidth, _originalDisplayHeight, _recordDisplayWidth, _recordDisplayHeight, _scaleX, _scaleY);
}

void InputHandler::ResetDisplayLayout() {
    _displayLayoutCnt = 0;
    memset(_displayLayouts, 0x00, sizeof(_displayLayouts));
}

bool InputHandler::AddDisplayLayout(int clientLeft, int clientTop, int clientWidth, int clientHeight, int displayOriginX, int displayOriginY, int displayWidth, int displayHeight, int displayId) {
    if (_displayLayoutCnt >= 16) {
        return false;
    }

    if (clientWidth <= 0 || clientHeight <= 0 || displayWidth <= 0 || displayHeight <= 0 || displayId <= 0) {
        return false;
    }

    _displayLayouts[_displayLayoutCnt].clientLeft = clientLeft;
    _displayLayouts[_displayLayoutCnt].clientTop = clientTop;
    _displayLayouts[_displayLayoutCnt].clientWidth = clientWidth;
    _displayLayouts[_displayLayoutCnt].clientHeight = clientHeight;
    _displayLayouts[_displayLayoutCnt].displayId = displayId;
    _displayLayouts[_displayLayoutCnt].displayOriginX = displayOriginX;
    _displayLayouts[_displayLayoutCnt].displayOriginY = displayOriginY;
    _displayLayouts[_displayLayoutCnt].scaleX = (float)displayWidth / (float)clientWidth;
    _displayLayouts[_displayLayoutCnt].scaleY = (float)displayHeight / (float)clientHeight;
    _displayLayoutCnt++;

    printf("AddDisplayLayout client: %d %d %d %d, display: %d %d %d %d, displayId: %d\n", clientLeft, clientTop, clientWidth, clientHeight, displayOriginX, displayOriginY, displayWidth, displayHeight, displayId);

    return true;
}

void InputHandler::HandleMousseInputEvent(xstream_t* cmd) {
    if (cmd == NULL) return;
        
    int key = xstream_readInt32(cmd);
    int clientX = xstream_readInt32(cmd);
    int clientY = xstream_readInt32(cmd);
    long long currentTime = GetCurrentEventTime();
    
    // If input interval is large due to minimize/restore, discard previous click state.
    if (_lastMouseInputEventTime != 0 && currentTime - _lastMouseInputEventTime > 1500) {
        RestorePreviousMouseKeydownEvent();
        
        _mouseClickCnt = 0;
        _lastMouseButton = -1;
        _lastMouseClickTime = 0;
    }
    _lastMouseInputEventTime = currentTime;
    
    MapClientPointToDisplayPoint(clientX, clientY, &clientX, &clientY);
    
    CGPoint point = CGPointMake(clientX, clientY);
    CGEventRef ev = NULL;
    int mouseEventNumber = 0;

    InputMapping::ScrollEvent scrollEvent;
    if (InputMapping::TranslateScrollEvent(key,
                                           AppConfig.shared.macNativeInputMappingEnabled,
                                           &scrollEvent)) {
        bool horizontal = scrollEvent.axis == InputMapping::ScrollAxis::Horizontal;
        WHEEL_STATE* wheelState = horizontal ? &_horizontalWheelState : &_verticalWheelState;
        int amount = GetMouseWheelMoveAmount(scrollEvent.direction, wheelState) * scrollEvent.direction;
        if (wheelState->isTrackpad) {
            PostTrackpadScrollEvent(amount, horizontal);
        }
        else {
            PostScrollEvent(horizontal ? 0 : amount, horizontal ? amount : 0, false);
        }
        return;
    }

    switch (key) {
        case XRDP_MOUSE_MOVE: {
            
            CGMouseButton btn = kCGMouseButtonLeft;
            CGEventType mouseMoveFlags = kCGEventMouseMoved;
            if (_mouseKeyStatus.downStatus.leftKeyDown) {
                mouseMoveFlags = kCGEventLeftMouseDragged;
                mouseEventNumber = _leftMouseEventNumber;
            }
            else if (_mouseKeyStatus.downStatus.rightKeyDown) {
                mouseMoveFlags = kCGEventRightMouseDragged;
                btn = kCGMouseButtonRight;
                mouseEventNumber = _rightMouseEventNumber;
            }
            
            ev = CGEventCreateMouseEvent(_eventRef, mouseMoveFlags, point, btn);
            
            // Some controls like Xcode minimap require these values to be set.
            int dx = clientX - _lastMousePosX;
            int dy = clientY - _lastMousePosY;
            
            CGEventSetIntegerValueField(ev, kCGMouseEventDeltaX, dx);
            CGEventSetIntegerValueField(ev, kCGMouseEventDeltaY, dy);
            
            _lastMousePosX = clientX;
            _lastMousePosY = clientY;
            
            break;
        }
        case XRDP_MOUSE_LBTNDOWN: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
            _mouseEventNumber = (_mouseEventNumber == INT_MAX) ? 1 : _mouseEventNumber + 1;
            _leftMouseEventNumber = _mouseEventNumber;
            mouseEventNumber = _leftMouseEventNumber;
            
            HandleMouseDoubleClick(ev, true, clientX, clientY, kCGMouseButtonLeft);
            
            _mouseKeyStatus.downStatus.leftKeyDown = 1;
            
            break;
        }
        case XRDP_MOUSE_LBTNUP: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
            mouseEventNumber = _leftMouseEventNumber;
            
            HandleMouseDoubleClick(ev, false, clientX, clientY, kCGMouseButtonLeft);
            
            _mouseKeyStatus.downStatus.leftKeyDown = 0;
            
            break;
        }
        case XRDP_MOUSE_RBTNDOWN: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventRightMouseDown, point, kCGMouseButtonRight);
            _mouseEventNumber = (_mouseEventNumber == INT_MAX) ? 1 : _mouseEventNumber + 1;
            _rightMouseEventNumber = _mouseEventNumber;
            mouseEventNumber = _rightMouseEventNumber;
            
            HandleMouseDoubleClick(ev, true, clientX, clientY, kCGMouseButtonRight);
            
            _mouseKeyStatus.downStatus.rightKeyDown = 1;

            break;
        }
        case XRDP_MOUSE_RBTNUP: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventRightMouseUp, point, kCGMouseButtonRight);
            mouseEventNumber = _rightMouseEventNumber;
            
            HandleMouseDoubleClick(ev, false, clientX, clientY, kCGMouseButtonRight);
            
            _mouseKeyStatus.downStatus.rightKeyDown = 0;

            break;
        }
        case XRDP_MOUSE_MBTNDOWN: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseDown, point, (CGMouseButton)2);
            _mouseEventNumber = (_mouseEventNumber == INT_MAX) ? 1 : _mouseEventNumber + 1;
            _wheelMouseEventNumber = _mouseEventNumber;
            mouseEventNumber = _wheelMouseEventNumber;
            
            _mouseKeyStatus.downStatus.wheelKeyDown = 1;
            
            break;
        }
        case XRDP_MOUSE_MBTNUP: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)2);
            mouseEventNumber = _wheelMouseEventNumber;
            
            _mouseKeyStatus.downStatus.wheelKeyDown = 0;
            
            break;
        }
        case XRDP_MOUSE_BBTNUP: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)3);
            mouseEventNumber = _backMouseEventNumber;
            
            _mouseKeyStatus.downStatus.backKeyDown = 0;
            
            break;
        }
        case XRDP_MOUSE_BBTNDOWN: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseDown, point, (CGMouseButton)3);
            _mouseEventNumber = (_mouseEventNumber == INT_MAX) ? 1 : _mouseEventNumber + 1;
            _backMouseEventNumber = _mouseEventNumber;
            mouseEventNumber = _backMouseEventNumber;
            
            _mouseKeyStatus.downStatus.backKeyDown = 1;
            
            break;
        }
        case XRDP_MOUSE_FBTNUP: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)4);
            mouseEventNumber = _forwardMouseEventNumber;
            
            _mouseKeyStatus.downStatus.forwardKeyDown = 0;
            
            break;
        }
        case XRDP_MOUSE_FBTNDOWN: {
            ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseDown, point, (CGMouseButton)4);
            _mouseEventNumber = (_mouseEventNumber == INT_MAX) ? 1 : _mouseEventNumber + 1;
            _forwardMouseEventNumber = _mouseEventNumber;
            mouseEventNumber = _forwardMouseEventNumber;
            
            _mouseKeyStatus.downStatus.forwardKeyDown = 1;

            break;
        }
        default:
            return;
    }

    if (ev == NULL) {
        return;
    }
    
    CGEventSetIntegerValueField(ev, kCGMouseEventNumber, mouseEventNumber);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
}

void InputHandler::HandleKeyboardInputEvent(xstream_t* cmd) {
    if (cmd == NULL || xstream_getRemaining(cmd) < (int)(sizeof(int) * 3)) return;
    
    int inputType = xstream_readInt32(cmd);
    int scanCode = xstream_readInt32(cmd);
    int flags = xstream_readInt32(cmd);

    if (inputType != XRDP_KEYBOARD_DOWN && inputType != XRDP_KEYBOARD_UP) {
        return;
    }

    bool keyDown = inputType == XRDP_KEYBOARD_DOWN;
    bool extended = (flags & 0x100) != 0;
    int normalizedScanCode = extended ? (scanCode & 0x7F) : scanCode;
    InputMapping::KeyEvent mapped = _inputMappingState.Translate(
        keyDown,
        normalizedScanCode,
        extended,
        AppConfig.shared.macNativeInputMappingEnabled);

    if (mapped.action == InputMapping::KeyAction::Ignore) {
        return;
    }
    if (mapped.action == InputMapping::KeyAction::SwitchInputSource) {
        if (mapped.keyDown) {
            dispatch_async(_keyboardQueue, ^{ BeginIMESwitch(); });
        }
        return;
    }

    KEYBOARD_EVENT event = {
        mapped.action,
        mapped.keyDown,
        (CGKeyCode)mapped.keyCode,
        (CGEventFlags)mapped.additionalFlags,
    };
    dispatch_async(_keyboardQueue, ^{ HandleQueuedKeyboardEvent(event); });
}

void InputHandler::HandleQueuedKeyboardEvent(const KEYBOARD_EVENT& event) {
    if (_keyboardShuttingDown) return;

    if (_imeSwitchState.active()) {
        if (_bufferedKeyboardEvents.size() < kMaxBufferedKeyboardEvents) {
            _bufferedKeyboardEvents.push_back(event);
            return;
        }

        NSLog(@"[InputHandler] IME keyboard buffer overflow; cancelling switch");
        _imeSwitchState.Cancel();
        FlushBufferedKeyboardEvents();
    }

    PostQueuedKeyboardEvent(event);
}

void InputHandler::PostQueuedKeyboardEvent(const KEYBOARD_EVENT& event) {
    if (event.action == InputMapping::KeyAction::ToggleCapsLockState) {
        if (event.keyDown) {
            _keyboardModifierFlags ^= kCGEventFlagMaskAlphaShift;
        }
        return;
    }
    if (event.action == InputMapping::KeyAction::MissionControl) {
        if (event.keyDown) {
            PostMissionControlShortcut();
        }
        return;
    }
    if (event.action != InputMapping::KeyAction::PostKey) {
        return;
    }

    CGEventRef ev = CGEventCreateKeyboardEvent(_keyboardEventRef, event.keyCode, event.keyDown);
    if (ev == NULL) {
        return;
    }

    ModifierStateChange modifierState = UpdateKeyboardModifierState(event.keyCode, event.keyDown);
    if (modifierState == ModifierStateChanged) {
        CGEventSetType(ev, kCGEventFlagsChanged);
    }
    else if (modifierState == ModifierStateUnchanged) {
        CFRelease(ev);
        return;
    }

    // Mission Control
    CGEventFlags eventFlags = _keyboardModifierFlags | event.additionalFlags;
    if ((eventFlags & kCGEventFlagMaskControl) != 0 &&
        (event.keyCode == kVK_UpArrow || event.keyCode == kVK_DownArrow ||
         event.keyCode == kVK_LeftArrow || event.keyCode == kVK_RightArrow)) {
        eventFlags |= kCGEventFlagMaskSecondaryFn;
    }
    CGEventSetFlags(ev, eventFlags);
    
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
}

void InputHandler::PostMissionControlShortcut() {
    const CGEventFlags flags = kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn;
    CGEventRef keyDown = CGEventCreateKeyboardEvent(_keyboardEventRef, kVK_UpArrow, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(_keyboardEventRef, kVK_UpArrow, false);
    if (keyDown != NULL) {
        CGEventSetFlags(keyDown, flags);
        CGEventPost(kCGSessionEventTap, keyDown);
        CFRelease(keyDown);
    }
    if (keyUp != NULL) {
        CGEventSetFlags(keyUp, flags);
        CGEventPost(kCGSessionEventTap, keyUp);
        CFRelease(keyUp);
    }
}

void InputHandler::HandleMouseDoubleClick(CGEventRef ev, bool mouseDown, int mouseX, int mouseY, int mouseButton) {
    if (mouseDown) {
        long long currentTime = GetCurrentEventTime();
        if (mouseButton == _lastMouseButton && currentTime - _lastMouseClickTime < 400) {
            int gap = abs(mouseX - _lastMouseClickPosX) + abs(mouseY - _lastMouseClickPosY);
            if (gap < 5) {
                _mouseClickCnt++;
            }
            else {
                _mouseClickCnt = 1;
            }
        }
        else {
            _mouseClickCnt = 1;
        }
        
        _lastMouseClickPosX = mouseX;
        _lastMouseClickPosY = mouseY;
        _lastMouseButton = mouseButton;
        _lastMouseClickTime = currentTime;
    }
    
    CGEventSetIntegerValueField(ev, kCGMouseEventClickState, _mouseClickCnt);
}

bool InputHandler::MapClientPointToDisplayPoint(int clientX, int clientY, int* outX, int* outY) {
    if (outX == NULL || outY == NULL) {
        return false;
    }

    for (int i = 0; i < _displayLayoutCnt; i++) {
        struct DISPLAY_LAYOUT* layout = &_displayLayouts[i];
        if (layout->clientWidth <= 0 || layout->clientHeight <= 0 || layout->displayId <= 0) {
            continue;
        }

        if (clientX < layout->clientLeft || clientY < layout->clientTop ||
            clientX >= layout->clientLeft + layout->clientWidth ||
            clientY >= layout->clientTop + layout->clientHeight) {
            continue;
        }

        int localX = clientX - layout->clientLeft;
        int localY = clientY - layout->clientTop;

        *outX = layout->displayOriginX + (int)((float)localX * layout->scaleX);
        *outY = layout->displayOriginY + (int)((float)localY * layout->scaleY);

        return true;
    }

    *outX = CalcPos(clientX, _scaleX);
    *outY = CalcPos(clientY, _scaleY);
    return false;
}

int InputHandler::CalcPos(int clientPos, float scale) {
    if (scale == 1.0f) return clientPos;
    
    float calc = clientPos * scale;
    
    if (calc < 0) return 0;
    
    return (int)calc;
}

long long InputHandler::GetCurrentEventTime() {
    struct timeval te;
    gettimeofday(&te, NULL);
    return te.tv_sec * 1000LL + te.tv_usec / 1000;
}

int InputHandler::GetMouseWheelMoveAmount(int direction, WHEEL_STATE* state) {
    const int kIdleGapMs = 180;
    const int kFastWheelGapMs = 18;
    const int kTrackpadGapMs = 45;
    const int kMouseConfirmGapMs = 80;
    const int kTrackpadMinAmount = 6;
    const int kTrackpadMaxAmount = 32;
    const int kMouseMinAmount = 1;
    const int kMouseMaxAmount = 7;

    if (direction > 0) {
        direction = 1;
    }
    else if (direction < 0) {
        direction = -1;
    }
    else {
        direction = 0;
    }
    
    long long currentTime = GetCurrentEventTime();
    long long gap = 0;
    bool newGesture = false;
    
    if (state == NULL) {
        return 0;
    }

    if (state->lastEventTime == 0) {
        newGesture = true;
    }
    else {
        gap = currentTime - state->lastEventTime;
        if (gap > kIdleGapMs) {
            newGesture = true;
        }
    }
    
    if (direction != 0 && state->lastDirection != 0 && direction != state->lastDirection) {
        newGesture = true;
    }
    
    if (newGesture) {
        state->eventBurstCount = 0;
        state->fastEventCount = 0;
    }
    else {
        state->eventBurstCount++;
    }
    
    // Only treat as trackpad when very short intervals come in consecutively.
    if (!newGesture && gap <= kFastWheelGapMs) {
        state->fastEventCount++;
    }
    else if (newGesture || gap >= kMouseConfirmGapMs) {
        state->fastEventCount = 0;
    }

    if (state->lastEventTime != 0) {
        if (state->isTrackpad) {
            if (gap >= kMouseConfirmGapMs) {
                state->isTrackpad = false;
            }
        }
        else if (!newGesture && gap <= kTrackpadGapMs && state->fastEventCount >= 2) {
            state->isTrackpad = true;
        }
        else if (gap >= kMouseConfirmGapMs) {
            state->isTrackpad = false;
        }
    }
    
    int target = 0;
    if (state->isTrackpad) {
        if (gap <= 14) {
            target = 32;
        }
        else if (gap <= 24) {
            target = 24;
        }
        else if (gap <= kTrackpadGapMs) {
            target = 18;
        }
        else {
            target = 14;
        }
        
        if (newGesture) {
            target = 12;
        }
        
        if (state->eventBurstCount > 18 && target > 16) {
            target -= 4;
        }
    }
    else {
        if (newGesture) {
            target = 2;
        }
        else if (gap <= 40) {
            target = 12;
        }
        else if (gap <= 60) {
            target = 8;
        }
        else if (gap <= 90) {
            target = 6;
        }
        else if (gap <= 130) {
            target = 5;
        }
        else {
            target = 3;
        }
    }
    
    if (newGesture) {
        state->smoothedAmount = (float)target;
    }
    else {
        float alpha = state->isTrackpad ? 0.35f : 0.65f;
        state->smoothedAmount = (state->smoothedAmount * (1.0f - alpha)) + (((float)target) * alpha);
    }
    
    int amount = (int)(state->smoothedAmount + 0.5f);
    if (state->isTrackpad) {
        if (amount < kTrackpadMinAmount) {
            amount = kTrackpadMinAmount;
        }
        else if (amount > kTrackpadMaxAmount) {
            amount = kTrackpadMaxAmount;
        }
    }
    else {
        if (amount < kMouseMinAmount) {
            amount = kMouseMinAmount;
        }
        else if (amount > kMouseMaxAmount) {
            amount = kMouseMaxAmount;
        }
    }
    
    state->lastEventTime = currentTime;
    state->lastDirection = direction;
    return amount;
}

void InputHandler::PostScrollEvent(int verticalAmount, int horizontalAmount, bool continuous) {
    CGScrollEventUnit unit = continuous ? kCGScrollEventUnitPixel : kCGScrollEventUnitLine;
    uint32_t wheelCount = horizontalAmount == 0 ? 1 : 2;
    CGEventRef ev = CGEventCreateScrollWheelEvent(NULL, unit, wheelCount,
                                                  verticalAmount, horizontalAmount);
    if (ev == NULL) {
        return;
    }

    // Trackpad-style scroll setting (for continuous events)
    if (continuous) {
        CGEventSetIntegerValueField(ev, kCGScrollWheelEventIsContinuous, 1);
    }

    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
}

void InputHandler::PostTrackpadScrollEvent(int amount, bool horizontal) {
    int absAmount = abs(amount);
    if (absAmount <= 0) {
        return;
    }

    int steps = 1;
    if (absAmount > 14) {
        steps = 3;
    }
    else if (absAmount > 8) {
        steps = 2;
    }

    int base = absAmount / steps;
    int remain = absAmount % steps;
    int sign = (amount < 0) ? -1 : 1;

    for (int i = 0; i < steps; i++) {
        int part = base + ((i < remain) ? 1 : 0);
        if (part <= 0) {
            continue;
        }
        int signedPart = part * sign;
        PostScrollEvent(horizontal ? 0 : signedPart,
                        horizontal ? signedPart : 0,
                        true);
    }
}

InputHandler::ModifierStateChange InputHandler::UpdateKeyboardModifierState(CGKeyCode key, bool isDown) {
    CGEventFlags oldFlags = _keyboardModifierFlags;
    CGEventFlags deviceFlag = 0;
    CGEventFlags groupFlag = 0;
    CGEventFlags groupDeviceFlags = 0;
    switch (key) {
        case 56: // Shift (Left)
            deviceFlag = kDeviceLeftShiftFlag;
            groupFlag = kCGEventFlagMaskShift;
            groupDeviceFlags = kDeviceLeftShiftFlag | kDeviceRightShiftFlag;
            break;
        case 60: // Shift (Right)
            deviceFlag = kDeviceRightShiftFlag;
            groupFlag = kCGEventFlagMaskShift;
            groupDeviceFlags = kDeviceLeftShiftFlag | kDeviceRightShiftFlag;
            break;
        case 59: // Control (Left)
            deviceFlag = kDeviceLeftControlFlag;
            groupFlag = kCGEventFlagMaskControl;
            groupDeviceFlags = kDeviceLeftControlFlag | kDeviceRightControlFlag;
            break;
        case 62: // Control (Right)
            deviceFlag = kDeviceRightControlFlag;
            groupFlag = kCGEventFlagMaskControl;
            groupDeviceFlags = kDeviceLeftControlFlag | kDeviceRightControlFlag;
            break;
        case 58: // Option (Left)
            deviceFlag = kDeviceLeftOptionFlag;
            groupFlag = kCGEventFlagMaskAlternate;
            groupDeviceFlags = kDeviceLeftOptionFlag | kDeviceRightOptionFlag;
            break;
        case 61: // Option (Right)
            deviceFlag = kDeviceRightOptionFlag;
            groupFlag = kCGEventFlagMaskAlternate; // Option key
            groupDeviceFlags = kDeviceLeftOptionFlag | kDeviceRightOptionFlag;
            break;
        //case 29: // Win (Ctrl)
        case 55: // Command (Left)
            deviceFlag = kDeviceLeftCommandFlag;
            groupFlag = kCGEventFlagMaskCommand;
            groupDeviceFlags = kDeviceLeftCommandFlag | kDeviceRightCommandFlag;
            break;
        case 54: // Command (Right)
            deviceFlag = kDeviceRightCommandFlag;
            groupFlag = kCGEventFlagMaskCommand;
            groupDeviceFlags = kDeviceLeftCommandFlag | kDeviceRightCommandFlag;
            break;
        case 57: // CapsLock
            if (isDown) _keyboardModifierFlags ^= kCGEventFlagMaskAlphaShift;
            return oldFlags != _keyboardModifierFlags ? ModifierStateChanged : ModifierStateUnchanged;
        default:
            return ModifierStateNotModifier; // normal key
    }

    if (isDown) {
        _keyboardModifierFlags |= deviceFlag | groupFlag;
    }
    else {
        _keyboardModifierFlags &= ~deviceFlag;
        if ((_keyboardModifierFlags & groupDeviceFlags) == 0) {
            _keyboardModifierFlags &= ~groupFlag;
        }
    }
        
    return oldFlags != _keyboardModifierFlags ? ModifierStateChanged : ModifierStateUnchanged;
}

void InputHandler::BeginIMESwitch() {
    if (_keyboardShuttingDown) return;

    IMESwitch::Transition transition = _imeSwitchState.RequestSwitch();
    if (transition.effect != IMESwitch::Effect::StartOperation) {
        return;
    }

    InputHandler* handler = this;
    dispatch_queue_t keyboardQueue = _keyboardQueue;
    std::shared_ptr<KEYBOARD_LIFETIME> lifetime = _keyboardLifetime;

    // The helper normally completes within 200ms, but it starts on the main
    // queue which may itself be busy. Enforce the buffering deadline on the
    // dedicated keyboard queue so keystrokes are never held longer than 200ms.
    if (transition.startDeadline) {
        uint64_t sessionGeneration = transition.sessionGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       keyboardQueue, ^{
            if (!__atomic_load_n(&lifetime->active, __ATOMIC_ACQUIRE)) return;
            IMESwitch::Transition expired =
                handler->_imeSwitchState.ExpireSession(sessionGeneration);
            if (expired.effect != IMESwitch::Effect::Finish) return;
            NSLog(@"[InputHandler] IME switch timed out after 0.200 seconds; flushing buffered keys");
            [SessionMetrics.shared recordIMETimeout];
            handler->FlushBufferedKeyboardEvents();
        });
    }

    StartIMESwitchOperation(transition.operationGeneration);
}

void InputHandler::StartIMESwitchOperation(uint64_t operationGeneration) {
    if (_keyboardShuttingDown) return;

    InputHandler* handler = this;
    dispatch_queue_t keyboardQueue = _keyboardQueue;
    std::shared_ptr<KEYBOARD_LIFETIME> lifetime = _keyboardLifetime;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!__atomic_load_n(&lifetime->active, __ATOMIC_ACQUIRE)) return;
        [CJKHelper selectNextInputSourceWithWorkaround:
            ^(BOOL success, NSString *targetSourceID, NSString *actualSourceID, NSTimeInterval elapsed) {
                NSLog(@"[InputHandler] IME switch generation=%llu success=%d target=%@ actual=%@ elapsed=%.3f",
                      (unsigned long long)operationGeneration,
                      success, targetSourceID, actualSourceID, elapsed);
                if (!__atomic_load_n(&lifetime->active, __ATOMIC_ACQUIRE)) return;
                dispatch_async(keyboardQueue, ^{
                    if (!__atomic_load_n(&lifetime->active, __ATOMIC_ACQUIRE)) return;
                    handler->CompleteIMESwitch(operationGeneration, success, elapsed);
                });
            }];
    });
}

void InputHandler::CompleteIMESwitch(uint64_t generation, bool success, double elapsed) {
    if (_keyboardShuttingDown) {
        return;
    }

    IMESwitch::Transition transition =
        _imeSwitchState.CompleteOperation(generation, success);
    if (transition.effect == IMESwitch::Effect::None) return;

    if (!success) {
        if (elapsed >= 0.199) {
            NSLog(@"[InputHandler] IME switch timed out after %.3f seconds; flushing buffered keys", elapsed);
            [SessionMetrics.shared recordIMETimeout];
        }
        else {
            NSLog(@"[InputHandler] IME switch failed after %.3f seconds; flushing buffered keys", elapsed);
        }
    }

    if (transition.effect == IMESwitch::Effect::StartOperation) {
        StartIMESwitchOperation(transition.operationGeneration);
        return;
    }

    FlushBufferedKeyboardEvents();
}

void InputHandler::FlushBufferedKeyboardEvents() {
    while (!_bufferedKeyboardEvents.empty()) {
        KEYBOARD_EVENT event = _bufferedKeyboardEvents.front();
        _bufferedKeyboardEvents.pop_front();
        PostQueuedKeyboardEvent(event);
    }
}

void InputHandler::RestorePreviousMouseKeydownEvent() {
    if (_mouseKeyStatus.status == 0) {
        return;
    }

    CGPoint point = CGPointMake(_lastMousePosX, _lastMousePosY);
    CGEventRef ev = NULL;

    if (_mouseKeyStatus.downStatus.leftKeyDown) {
        ev = CGEventCreateMouseEvent(_eventRef, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
        if (ev != NULL) {
            CGEventPost(kCGSessionEventTap, ev);
            CFRelease(ev);
        }
    }

    if (_mouseKeyStatus.downStatus.rightKeyDown) {
        ev = CGEventCreateMouseEvent(_eventRef, kCGEventRightMouseUp, point, kCGMouseButtonRight);
        if (ev != NULL) {
            CGEventPost(kCGSessionEventTap, ev);
            CFRelease(ev);
        }
    }

    if (_mouseKeyStatus.downStatus.wheelKeyDown) {
        ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)2);
        if (ev != NULL) {
            CGEventPost(kCGSessionEventTap, ev);
            CFRelease(ev);
        }
    }

    if (_mouseKeyStatus.downStatus.backKeyDown) {
        ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)3);
        if (ev != NULL) {
            CGEventPost(kCGSessionEventTap, ev);
            CFRelease(ev);
        }
    }

    if (_mouseKeyStatus.downStatus.forwardKeyDown) {
        ev = CGEventCreateMouseEvent(_eventRef, kCGEventOtherMouseUp, point, (CGMouseButton)4);
        if (ev != NULL) {
            CGEventPost(kCGSessionEventTap, ev);
            CFRelease(ev);
        }
    }

    _mouseKeyStatus.status = 0;
}
