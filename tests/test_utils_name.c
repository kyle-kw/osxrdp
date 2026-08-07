#include "harness.h"
#include "utils.h"

#include <string.h>

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

int main(void) {
    printf("== test_utils_name ==\n");
    RUN_TEST(null_or_empty_prefix_fails);
    RUN_TEST(normal_and_lockscreen_names);
    RUN_TEST(buffer_too_small_fails);
    return test_main_finish("test_utils_name");
}
