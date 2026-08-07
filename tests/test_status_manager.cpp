#include "harness.h"
#include "../osxup/Status/StatusManager.h"

TEST_CASE(test_check_can_paint_init) {
    StatusManager sm;
    EXPECT_TRUE(sm.CheckCanPaint() == false);
}

TEST_CASE(test_check_can_paint_request_session) {
    StatusManager sm;
    sm.SetRequestSession();
    EXPECT_TRUE(sm.CheckCanPaint() == false);
}

TEST_CASE(test_check_can_paint_agent_connecting) {
    StatusManager sm;
    sm.SetAgentConnecting(false);
    EXPECT_TRUE(sm.CheckCanPaint() == false);
}

TEST_CASE(test_check_can_paint_agent_record) {
    StatusManager sm;
    sm.SetAgentRecordStart(false);
    EXPECT_TRUE(sm.CheckCanPaint() == true);
}

TEST_CASE(test_check_can_paint_agent_record_lockscreen) {
    StatusManager sm;
    sm.SetAgentRecordStart(true);
    EXPECT_TRUE(sm.CheckCanPaint() == true);
}

TEST_CASE(test_check_can_paint_suppressed) {
    StatusManager sm;
    sm.SetAgentRecordStart(false);
    EXPECT_TRUE(sm.CheckCanPaint() == true);
    sm.SetSuppressed(true);
    EXPECT_TRUE(sm.CheckCanPaint() == false);
    sm.SetSuppressed(false);
    EXPECT_TRUE(sm.CheckCanPaint() == true);
}

TEST_CASE(test_check_need_terminate_initial) {
    StatusManager sm;
    EXPECT_TRUE(sm.CheckNeedTerminate() == false);
}

TEST_CASE(test_check_need_terminate_after_stopping) {
    StatusManager sm;
    sm.SetStopping();
    EXPECT_TRUE(sm.CheckNeedTerminate() == true);
}

TEST_CASE(test_sticky_terminate) {
    StatusManager sm;
    sm.SetStopping();
    // All Set* calls should be no-ops after SetStopping
    sm.SetRequestSession();
    EXPECT_TRUE(sm.CheckNeedTerminate() == true);
    sm.SetAgentConnecting(false);
    EXPECT_TRUE(sm.CheckNeedTerminate() == true);
    sm.SetAgentConnected(false);
    EXPECT_TRUE(sm.CheckNeedTerminate() == true);
    sm.SetAgentRecordStart(false);
    EXPECT_TRUE(sm.CheckNeedTerminate() == true);
}

TEST_CASE(test_lockscreen_variants) {
    StatusManager sm;
    sm.SetAgentConnected(true);
    EXPECT_TRUE(sm.CheckInLockscreen() == true);
    EXPECT_TRUE(sm.CheckReconnection() == false);
}

TEST_CASE(test_check_reconnection_lockscreen_record) {
    StatusManager sm;
    sm.SetAgentRecordStart(true);
    EXPECT_TRUE(sm.CheckReconnection() == true);
    EXPECT_TRUE(sm.CheckInLockscreen() == false);
}

TEST_CASE(test_check_reconnection_normal_record) {
    StatusManager sm;
    sm.SetAgentRecordStart(false);
    EXPECT_TRUE(sm.CheckReconnection() == false);
}

TEST_CASE(test_check_init_status) {
    StatusManager sm;
    EXPECT_TRUE(sm.CheckInitStatus() == true);
    sm.SetRequestSession();
    EXPECT_TRUE(sm.CheckInitStatus() == true);
    sm.SetAgentConnecting(false);
    EXPECT_TRUE(sm.CheckInitStatus() == false);
}

int main(void) {
    RUN_TEST(test_check_can_paint_init);
    RUN_TEST(test_check_can_paint_request_session);
    RUN_TEST(test_check_can_paint_agent_connecting);
    RUN_TEST(test_check_can_paint_agent_record);
    RUN_TEST(test_check_can_paint_agent_record_lockscreen);
    RUN_TEST(test_check_can_paint_suppressed);
    RUN_TEST(test_check_need_terminate_initial);
    RUN_TEST(test_check_need_terminate_after_stopping);
    RUN_TEST(test_sticky_terminate);
    RUN_TEST(test_lockscreen_variants);
    RUN_TEST(test_check_reconnection_lockscreen_record);
    RUN_TEST(test_check_reconnection_normal_record);
    RUN_TEST(test_check_init_status);
    return test_main_finish("test_status_manager");
}
