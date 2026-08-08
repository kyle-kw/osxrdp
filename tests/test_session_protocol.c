#include "harness.h"
#include "osxrdp/session_protocol.h"

TEST_CASE(valid_request_has_exactly_one_utf8_username) {
    xstream_t* writer = xstream_create(64);
    EXPECT_NOT_NULL(writer);
    EXPECT_EQ_INT(xstream_writeStr(writer, "alice", 5), 0);
    int dataLen = 0;
    const void* data = xstream_get_raw_buffer(writer, &dataLen);
    xstream_t* reader = xstream_create_for_read((void*)data, dataLen);
    const char* username = NULL;
    int usernameLen = 0;
    EXPECT_EQ_INT(osxrdp_parse_session_request(reader, &username, &usernameLen), 0);
    EXPECT_EQ_INT(usernameLen, 5);
    EXPECT_STREQ(username, "alice");
    xstream_free(reader);
    xstream_free(writer);
}

TEST_CASE(missing_invalid_and_trailing_fields_are_rejected) {
    xstream_t* writer = xstream_create(64);
    EXPECT_NOT_NULL(writer);
    EXPECT_EQ_INT(xstream_writeInt32(writer, 0), 0);
    int dataLen = 0;
    const void* data = xstream_get_raw_buffer(writer, &dataLen);
    xstream_t* reader = xstream_create_for_read((void*)data, dataLen);
    const char* username = NULL;
    int usernameLen = 0;
    EXPECT_EQ_INT(osxrdp_parse_session_request(reader, &username, &usernameLen), 1);
    xstream_free(reader);
    xstream_free(writer);

    const char invalid[] = {(char)0xc0, (char)0xaf, '\0'};
    writer = xstream_create(64);
    EXPECT_EQ_INT(xstream_writeStr(writer, invalid, 2), 0);
    data = xstream_get_raw_buffer(writer, &dataLen);
    reader = xstream_create_for_read((void*)data, dataLen);
    EXPECT_EQ_INT(osxrdp_parse_session_request(reader, &username, &usernameLen), 1);
    xstream_free(reader);
    xstream_free(writer);

    writer = xstream_create(64);
    EXPECT_EQ_INT(xstream_writeStr(writer, "alice", 5), 0);
    EXPECT_EQ_INT(xstream_writeInt32(writer, 123), 0);
    data = xstream_get_raw_buffer(writer, &dataLen);
    reader = xstream_create_for_read((void*)data, dataLen);
    EXPECT_EQ_INT(osxrdp_parse_session_request(reader, &username, &usernameLen), 1);
    xstream_free(reader);
    xstream_free(writer);
}

TEST_CASE(pending_loginwindow_session_is_reused_only_for_ten_seconds) {
    EXPECT_TRUE(osxrdp_pending_session_is_reusable(42, 1000, 1000));
    EXPECT_TRUE(osxrdp_pending_session_is_reusable(42, 1000, 11000));
    EXPECT_TRUE(!osxrdp_pending_session_is_reusable(42, 1000, 11001));
    EXPECT_TRUE(!osxrdp_pending_session_is_reusable(-1, 1000, 1001));
    EXPECT_TRUE(!osxrdp_pending_session_is_reusable(42, 1000, 999));
}

int main(void) {
    RUN_TEST(valid_request_has_exactly_one_utf8_username);
    RUN_TEST(missing_invalid_and_trailing_fields_are_rejected);
    RUN_TEST(pending_loginwindow_session_is_reused_only_for_ten_seconds);
    return test_main_finish("test_session_protocol");
}
