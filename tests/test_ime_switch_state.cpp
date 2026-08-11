#include "harness.h"
#include "../ServerApp/OSXRDP/ScreenRecorder/IMESwitchState.h"

using IMESwitch::Effect;
using IMESwitch::State;
using IMESwitch::Transition;

static void expect_effect(const Transition& transition, Effect effect) {
    EXPECT_EQ_INT(effect, transition.effect);
}

TEST_CASE(first_request_starts_operation_and_deadline) {
    State state;

    Transition started = state.RequestSwitch();
    expect_effect(started, Effect::StartOperation);
    EXPECT_TRUE(started.startDeadline);
    EXPECT_TRUE(state.active());
}

TEST_CASE(two_presses_run_two_serial_operations) {
    State state;

    Transition first = state.RequestSwitch();
    Transition queued = state.RequestSwitch();
    expect_effect(queued, Effect::None);

    Transition second =
        state.CompleteOperation(first.operationGeneration, true);
    expect_effect(second, Effect::StartOperation);
    EXPECT_TRUE(!second.startDeadline);
    EXPECT_TRUE(second.operationGeneration != first.operationGeneration);
    EXPECT_TRUE(state.active());

    Transition finished =
        state.CompleteOperation(second.operationGeneration, true);
    expect_effect(finished, Effect::Finish);
    EXPECT_TRUE(!state.active());
}

TEST_CASE(three_presses_coalesce_to_one_operation) {
    State state;

    Transition first = state.RequestSwitch();
    state.RequestSwitch();
    state.RequestSwitch();

    Transition finished =
        state.CompleteOperation(first.operationGeneration, true);
    expect_effect(finished, Effect::Finish);
    EXPECT_TRUE(!state.active());
}

TEST_CASE(stale_deadline_cannot_cancel_new_session) {
    State state;

    Transition first = state.RequestSwitch();
    expect_effect(state.CompleteOperation(first.operationGeneration, true),
                  Effect::Finish);
    Transition second = state.RequestSwitch();

    expect_effect(state.ExpireSession(first.sessionGeneration), Effect::None);
    EXPECT_TRUE(state.active());
    expect_effect(state.CompleteOperation(second.operationGeneration, true),
                  Effect::Finish);
}

TEST_CASE(stale_completion_cannot_finish_current_operation) {
    State state;

    Transition first = state.RequestSwitch();
    expect_effect(state.ExpireSession(first.sessionGeneration), Effect::Finish);
    Transition second = state.RequestSwitch();

    expect_effect(state.CompleteOperation(first.operationGeneration, true),
                  Effect::None);
    EXPECT_TRUE(state.active());
    expect_effect(state.CompleteOperation(second.operationGeneration, true),
                  Effect::Finish);
}

TEST_CASE(failure_clears_queued_toggle) {
    State state;

    Transition first = state.RequestSwitch();
    state.RequestSwitch();

    expect_effect(state.CompleteOperation(first.operationGeneration, false),
                  Effect::Finish);
    EXPECT_TRUE(!state.active());
}

TEST_CASE(deadline_and_cancel_invalidate_active_operation) {
    State state;

    Transition first = state.RequestSwitch();
    state.RequestSwitch();
    expect_effect(state.ExpireSession(first.sessionGeneration), Effect::Finish);
    expect_effect(state.CompleteOperation(first.operationGeneration, true),
                  Effect::None);

    Transition second = state.RequestSwitch();
    expect_effect(state.Cancel(), Effect::Finish);
    expect_effect(state.CompleteOperation(second.operationGeneration, true),
                  Effect::None);
    EXPECT_TRUE(!state.active());
}

int main(void) {
    RUN_TEST(first_request_starts_operation_and_deadline);
    RUN_TEST(two_presses_run_two_serial_operations);
    RUN_TEST(three_presses_coalesce_to_one_operation);
    RUN_TEST(stale_deadline_cannot_cancel_new_session);
    RUN_TEST(stale_completion_cannot_finish_current_operation);
    RUN_TEST(failure_clears_queued_toggle);
    RUN_TEST(deadline_and_cancel_invalidate_active_operation);
    return test_main_finish("test_ime_switch_state");
}
