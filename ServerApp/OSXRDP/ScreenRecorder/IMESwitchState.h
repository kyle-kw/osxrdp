#ifndef IMESwitchState_h
#define IMESwitchState_h

#include <stdint.h>

namespace IMESwitch {

enum class Effect {
    None,
    StartOperation,
    Finish,
};

struct Transition {
    Effect effect;
    uint64_t operationGeneration;
    uint64_t sessionGeneration;
    bool startDeadline;
};

class State {
public:
    State();

    Transition RequestSwitch();
    Transition CompleteOperation(uint64_t operationGeneration, bool success);
    Transition ExpireSession(uint64_t sessionGeneration);
    Transition Cancel();

    bool active() const;

private:
    Transition MakeTransition(Effect effect, bool startDeadline) const;

    bool _active;
    bool _queuedToggle;
    uint64_t _operationGeneration;
    uint64_t _sessionGeneration;
};

} // namespace IMESwitch

#endif /* IMESwitchState_h */
