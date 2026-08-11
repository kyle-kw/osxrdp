#include "harness.h"
#include <string.h>
#include <stdlib.h>

// Include the source under test with stubs
// We need to stub xipc_send_data to capture the buffer
#include "ipc.h"
#include "xstream.h"
#include "../osxup/Command/Command.h"
#include "osxrdp/packet.h"
#include "osxrdp/stream_policy.h"

// Captured send buffer
static char g_capturedBuffer[4096];
static int g_capturedLen = 0;

// Stub: capture instead of actually sending
extern "C" int xipc_send_data(xipc_t* ipc, const void* data, int len) {
    (void)ipc;
    if (len > (int)sizeof(g_capturedBuffer)) len = (int)sizeof(g_capturedBuffer);
    memcpy(g_capturedBuffer, data, len);
    g_capturedLen = len;
    return 0;
}

static int32_t read_int32_at(int offset) {
    if (offset + 4 > g_capturedLen) return -999;
    int32_t val;
    memcpy(&val, g_capturedBuffer + offset, sizeof(val));
    return val;
}

TEST_CASE(test_send_record_stop_msg) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    cmd.SendRecordStopMsg(&dummyIpc);

    EXPECT_EQ_INT(g_capturedLen, 8);
    EXPECT_EQ_INT(read_int32_at(0), OSXRDP_CMDTYPE_SCREEN);
    EXPECT_EQ_INT(read_int32_at(4), OSXRDP_PACKETTYPE_REQ_SCREENOFF);
}

TEST_CASE(test_send_mouse_input_msg) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    cmd.SendMouseInputMsg(&dummyIpc, XRDP_MOUSE_MOVE, 100, 200);

    // Packed struct: {cmdType, packetType, inputType, x, y} = 20 bytes
    EXPECT_EQ_INT(g_capturedLen, 20);
    EXPECT_EQ_INT(read_int32_at(0), OSXRDP_CMDTYPE_SCREEN);
    EXPECT_EQ_INT(read_int32_at(4), OSXRDP_PACKETTYPE_MOUSEEVT);
    EXPECT_EQ_INT(read_int32_at(8), XRDP_MOUSE_MOVE);
    EXPECT_EQ_INT(read_int32_at(12), 100);
    EXPECT_EQ_INT(read_int32_at(16), 200);
}

TEST_CASE(test_send_keyboard_input_msg) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    cmd.SendKeyboardInputMsg(&dummyIpc, XRDP_KEYBOARD_DOWN, 65, 0);

    EXPECT_EQ_INT(g_capturedLen, 20);
    EXPECT_EQ_INT(read_int32_at(0), OSXRDP_CMDTYPE_SCREEN);
    EXPECT_EQ_INT(read_int32_at(4), OSXRDP_PACKETTYPE_KEYBOARDEVT);
    EXPECT_EQ_INT(read_int32_at(8), XRDP_KEYBOARD_DOWN);
    EXPECT_EQ_INT(read_int32_at(12), 65);
    EXPECT_EQ_INT(read_int32_at(16), 0);
}

TEST_CASE(test_send_screen_resize_msg) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    cmd.SendScreenResizeMsg(&dummyIpc, 1920, 1080, 60, 0, 0, 0, NULL,
                            OSXRDP_STREAM_POLICY_VERSION, OSXRDP_STREAM_QUALITY_HIGH);

    // Wire: [CMDTYPE_SCREEN, REQ_SCREENRESIZE, 0(unused), width, height, 60(fps), recordFormat, useVirtualmon, monitorCount(1), 0, 0, width, height, 1]
    EXPECT_EQ_INT(read_int32_at(0), OSXRDP_CMDTYPE_SCREEN);
    EXPECT_EQ_INT(read_int32_at(4), OSXRDP_PACKETTYPE_REQ_SCREENRESIZE);
    EXPECT_EQ_INT(read_int32_at(8), 0);               // unused
    EXPECT_EQ_INT(read_int32_at(12), 1920);            // width (even-aligned)
    EXPECT_EQ_INT(read_int32_at(16), 1080);            // height (even-aligned)
    EXPECT_EQ_INT(read_int32_at(20), 60);              // fps
    EXPECT_EQ_INT(read_int32_at(28), 0);               // useVirtualmon
    EXPECT_EQ_INT(read_int32_at(32), 1);               // monitorCount (synthesized)
    EXPECT_EQ_INT(read_int32_at(36), 0);               // left
    EXPECT_EQ_INT(read_int32_at(40), 0);               // top
    EXPECT_EQ_INT(read_int32_at(44), 1920);            // right
    EXPECT_EQ_INT(read_int32_at(48), 1080);            // bottom
    EXPECT_EQ_INT(read_int32_at(52), 1);               // is_primary
    EXPECT_EQ_INT(read_int32_at(56), OSXRDP_STREAM_POLICY_VERSION);
    EXPECT_EQ_INT(read_int32_at(60), OSXRDP_STREAM_QUALITY_HIGH);
}

TEST_CASE(test_send_screen_resize_msg_odd_dimensions) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    cmd.SendScreenResizeMsg(&dummyIpc, 1921, 1081, 60, 0, 0, 0, NULL,
                            OSXRDP_STREAM_POLICY_VERSION, OSXRDP_STREAM_QUALITY_HIGH);

    // Odd dimensions should be even-aligned
    EXPECT_EQ_INT(read_int32_at(12), 1920);
    EXPECT_EQ_INT(read_int32_at(16), 1080);
    EXPECT_EQ_INT(read_int32_at(44), 1920);  // right = even-aligned width
    EXPECT_EQ_INT(read_int32_at(48), 1080);  // bottom = even-aligned height
}

TEST_CASE(test_send_screen_resize_msg_with_monitors) {
    Command cmd;
    xipc_t dummyIpc = {};
    g_capturedLen = 0;
    struct monitor_info monitors[2] = {};
    monitors[0].left = 0;
    monitors[0].top = 0;
    monitors[0].right = 1920;
    monitors[0].bottom = 1080;
    monitors[0].is_primary = 1;
    monitors[1].left = 1920;
    monitors[1].top = 0;
    monitors[1].right = 3840;
    monitors[1].bottom = 1080;
    monitors[1].is_primary = 0;

    cmd.SendScreenResizeMsg(&dummyIpc, 3840, 1080, 60, 1, 1, 2, monitors,
                            OSXRDP_STREAM_POLICY_VERSION, OSXRDP_STREAM_QUALITY_HIGH);

    EXPECT_EQ_INT(read_int32_at(0), OSXRDP_CMDTYPE_SCREEN);
    EXPECT_EQ_INT(read_int32_at(4), OSXRDP_PACKETTYPE_REQ_SCREENRESIZE);
    EXPECT_EQ_INT(read_int32_at(32), 2);  // monitorCount

    // Monitor 0
    EXPECT_EQ_INT(read_int32_at(36), 0);     // left
    EXPECT_EQ_INT(read_int32_at(40), 0);     // top
    EXPECT_EQ_INT(read_int32_at(44), 1920);  // right
    EXPECT_EQ_INT(read_int32_at(48), 1080);  // bottom
    EXPECT_EQ_INT(read_int32_at(52), 1);     // is_primary

    // Monitor 1
    EXPECT_EQ_INT(read_int32_at(56), 1920);  // left
    EXPECT_EQ_INT(read_int32_at(60), 0);     // top
    EXPECT_EQ_INT(read_int32_at(64), 3840);  // right
    EXPECT_EQ_INT(read_int32_at(68), 1080);  // bottom
    EXPECT_EQ_INT(read_int32_at(72), 0);     // is_primary
}

TEST_CASE(test_send_record_start_clamps_monitor_count) {
    Command cmd;
    xipc_t dummyIpc = {};
    struct monitor_info monitors[17] = {};
    for (int i = 0; i < 17; i++) {
        monitors[i].right = i + 1;
    }

    g_capturedLen = 0;
    cmd.SendRecordStartMsg(&dummyIpc, 1920, 1080, 60, 0, 1, 17, monitors,
                           OSXRDP_STREAM_POLICY_VERSION, OSXRDP_STREAM_QUALITY_HIGH);

    EXPECT_EQ_INT(read_int32_at(32), 16);
    EXPECT_EQ_INT(g_capturedLen, (11 + 16 * 5) * (int)sizeof(int32_t));
    EXPECT_EQ_INT(read_int32_at(36 + 15 * 20 + 8), 16);
    EXPECT_EQ_INT(read_int32_at(36 + 16 * 20), OSXRDP_STREAM_POLICY_VERSION);
}

int main(void) {
    RUN_TEST(test_send_record_stop_msg);
    RUN_TEST(test_send_mouse_input_msg);
    RUN_TEST(test_send_keyboard_input_msg);
    RUN_TEST(test_send_screen_resize_msg);
    RUN_TEST(test_send_screen_resize_msg_odd_dimensions);
    RUN_TEST(test_send_screen_resize_msg_with_monitors);
    RUN_TEST(test_send_record_start_clamps_monitor_count);
    return test_main_finish("test_command_packing");
}
