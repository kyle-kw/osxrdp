#include "harness.h"
#include "../ServerApp/OSXRDP/Utils/ConnectionState.h"

TEST_CASE(missing_permission_takes_priority) {
    EXPECT_EQ_INT(ConnectionState::NeedsPermissions,
                  ConnectionStateResolve(false, true, true, true, false, true));
    EXPECT_EQ_INT(ConnectionState::NeedsPermissions,
                  ConnectionStateResolve(true, false, false, false, true, false));
}

TEST_CASE(starting_is_exposed_after_permissions) {
    EXPECT_EQ_INT(ConnectionState::Starting,
                  ConnectionStateResolve(true, true, false, false, true, false));
}

TEST_CASE(running_service_distinguishes_ready_and_connected) {
    EXPECT_EQ_INT(ConnectionState::Ready,
                  ConnectionStateResolve(true, true, true, false, false, false));
    EXPECT_EQ_INT(ConnectionState::Connected,
                  ConnectionStateResolve(true, true, true, true, false, false));
}

TEST_CASE(stopped_and_failed_are_distinct) {
    EXPECT_EQ_INT(ConnectionState::Stopped,
                  ConnectionStateResolve(true, true, false, false, false, false));
    EXPECT_EQ_INT(ConnectionState::Failed,
                  ConnectionStateResolve(true, true, false, false, false, true));
}

TEST_CASE(primary_actions_match_states) {
    EXPECT_EQ_INT(ConnectionPrimaryAction::SetUpPermissions,
                  ConnectionPrimaryActionForState(ConnectionState::NeedsPermissions));
    EXPECT_EQ_INT(ConnectionPrimaryAction::None,
                  ConnectionPrimaryActionForState(ConnectionState::Starting));
    EXPECT_EQ_INT(ConnectionPrimaryAction::StopService,
                  ConnectionPrimaryActionForState(ConnectionState::Ready));
    EXPECT_EQ_INT(ConnectionPrimaryAction::StopService,
                  ConnectionPrimaryActionForState(ConnectionState::Connected));
    EXPECT_EQ_INT(ConnectionPrimaryAction::StartService,
                  ConnectionPrimaryActionForState(ConnectionState::Stopped));
    EXPECT_EQ_INT(ConnectionPrimaryAction::Retry,
                  ConnectionPrimaryActionForState(ConnectionState::Failed));
}

TEST_CASE(launch_auto_start_requires_intent_permissions_and_no_agent) {
    EXPECT_TRUE(ConnectionShouldStartOnLaunch(true, true, false));
    EXPECT_TRUE(!ConnectionShouldStartOnLaunch(false, true, false));
    EXPECT_TRUE(!ConnectionShouldStartOnLaunch(true, false, false));
    EXPECT_TRUE(!ConnectionShouldStartOnLaunch(true, true, true));
}

TEST_CASE(permission_transition_auto_starts_only_once) {
    EXPECT_TRUE(ConnectionShouldAutoStartAfterRefresh(true, false, true, false, false));
    EXPECT_TRUE(!ConnectionShouldAutoStartAfterRefresh(true, true, true, false, false));
    EXPECT_TRUE(!ConnectionShouldAutoStartAfterRefresh(false, false, true, false, false));
    EXPECT_TRUE(!ConnectionShouldAutoStartAfterRefresh(true, false, true, true, false));
    EXPECT_TRUE(!ConnectionShouldAutoStartAfterRefresh(true, false, true, false, true));
}

int main(void) {
    RUN_TEST(missing_permission_takes_priority);
    RUN_TEST(starting_is_exposed_after_permissions);
    RUN_TEST(running_service_distinguishes_ready_and_connected);
    RUN_TEST(stopped_and_failed_are_distinct);
    RUN_TEST(primary_actions_match_states);
    RUN_TEST(launch_auto_start_requires_intent_permissions_and_no_agent);
    RUN_TEST(permission_transition_auto_starts_only_once);
    return test_main_finish("test_connection_state");
}
