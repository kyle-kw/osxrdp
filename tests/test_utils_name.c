#include "harness.h"
#include "utils.h"

#include <string.h>
#include <stdlib.h>

TEST_CASE(null_or_empty_prefix_fails) {
    char buf[64];
    EXPECT_EQ_INT(get_object_name(1, NULL, buf, (int)sizeof(buf), 0), 0);
    EXPECT_EQ_INT(get_object_name(1, "", buf, (int)sizeof(buf), 0), 0);
}

TEST_CASE(normal_and_lockscreen_names) {
    char buf[64];
    int n = get_object_name(42, "/tmp/osxrdp", buf, (int)sizeof(buf), 0);
    EXPECT_TRUE(n > 0);
    EXPECT_STREQ(buf, "/tmp/osxrdp_42");

    n = get_object_name(42, "/tmp/osxrdp", buf, (int)sizeof(buf), 1);
    EXPECT_TRUE(n > 0);
    EXPECT_STREQ(buf, "/tmp/osxrdp_l_42");
}

TEST_CASE(buffer_too_small_fails) {
    char buf[8];
    EXPECT_EQ_INT(get_object_name(1, "/tmp/osxrdp", buf, (int)sizeof(buf), 0), 0);
}

TEST_CASE(private_socket_paths_are_uid_scoped) {
    char buf[128];
    EXPECT_TRUE(osxrdp_get_sessionmanager_socket_path(buf, (int)sizeof(buf)) > 0);
    EXPECT_STREQ(buf, "/var/run/osxrdp/sessionmanager.sock");

    EXPECT_TRUE(osxrdp_get_agent_socket_directory(501, buf, (int)sizeof(buf)) > 0);
    EXPECT_STREQ(buf, "/tmp/osxrdp-501");

    EXPECT_TRUE(osxrdp_get_agent_socket_path(501, 77, buf, (int)sizeof(buf), 0) > 0);
    EXPECT_STREQ(buf, "/tmp/osxrdp-501/agent-77.sock");
    EXPECT_TRUE(osxrdp_get_agent_socket_path(0, 77, buf, (int)sizeof(buf), 1) > 0);
    EXPECT_STREQ(buf, "/tmp/osxrdp-0/agent-lock-77.sock");
    EXPECT_EQ_INT(osxrdp_get_agent_socket_path(501, 0, buf, (int)sizeof(buf), 0), 0);
}

TEST_CASE(username_validation_is_strict_utf8_and_bounded) {
    EXPECT_TRUE(osxrdp_validate_utf8_username("alice", 5));
    EXPECT_TRUE(osxrdp_validate_utf8_username("Jos\xc3\xa9", 5));
    EXPECT_TRUE(!osxrdp_validate_utf8_username(NULL, 1));
    EXPECT_TRUE(!osxrdp_validate_utf8_username("", 0));

    const char embeddedNul[] = {'a', '\0', 'b', '\0'};
    EXPECT_TRUE(!osxrdp_validate_utf8_username(embeddedNul, 3));
    const char invalidUtf8[] = {(char)0xc0, (char)0xaf, '\0'};
    EXPECT_TRUE(!osxrdp_validate_utf8_username(invalidUtf8, 2));
    const char truncatedUtf8[] = {(char)0xe2, (char)0x82, '\0'};
    EXPECT_TRUE(!osxrdp_validate_utf8_username(truncatedUtf8, 2));

    char maximum[262];
    memset(maximum, 'a', 260);
    maximum[260] = '\0';
    EXPECT_TRUE(osxrdp_validate_utf8_username(maximum, 260));
    maximum[260] = 'a';
    maximum[261] = '\0';
    EXPECT_TRUE(!osxrdp_validate_utf8_username(maximum, 261));
}

int main(void) {
    printf("== test_utils_name ==\n");
    RUN_TEST(null_or_empty_prefix_fails);
    RUN_TEST(normal_and_lockscreen_names);
    RUN_TEST(buffer_too_small_fails);
    RUN_TEST(private_socket_paths_are_uid_scoped);
    RUN_TEST(username_validation_is_strict_utf8_and_bounded);
    return test_main_finish("test_utils_name");
}
