#include "IMESwitchState.h"

namespace IMESwitch {

State::State() :
    _active(false),
    _queuedToggle(false),
    _operationGeneration(0),
    _sessionGeneration(0) {
}

Transition State::RequestSwitch() {
    if (_active) {
        _queuedToggle = !_queuedToggle;
        return MakeTransition(Effect::None, false);
    }

    _active = true;
    _queuedToggle = false;
    _operationGeneration++;
    _sessionGeneration++;
    return MakeTransition(Effect::StartOperation, true);
}

Transition State::CompleteOperation(uint64_t operationGeneration, bool success) {
    if (!_active || operationGeneration != _operationGeneration) {
        return MakeTransition(Effect::None, false);
    }

    if (success && _queuedToggle) {
        _queuedToggle = false;
        _operationGeneration++;
        return MakeTransition(Effect::StartOperation, false);
    }

    _active = false;
    _queuedToggle = false;
    return MakeTransition(Effect::Finish, false);
}

Transition State::ExpireSession(uint64_t sessionGeneration) {
    if (!_active || sessionGeneration != _sessionGeneration) {
        return MakeTransition(Effect::None, false);
    }

    _active = false;
    _queuedToggle = false;
    _operationGeneration++;
    return MakeTransition(Effect::Finish, false);
}

Transition State::Cancel() {
    if (!_active) {
        return MakeTransition(Effect::None, false);
    }

    _active = false;
    _queuedToggle = false;
    _operationGeneration++;
    _sessionGeneration++;
    return MakeTransition(Effect::Finish, false);
}

bool State::active() const {
    return _active;
}

Transition State::MakeTransition(Effect effect, bool startDeadline) const {
    return {
        effect,
        _operationGeneration,
        _sessionGeneration,
        startDeadline,
    };
}

} // namespace IMESwitch
