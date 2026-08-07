#include "harness.h"
#include "xshm.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

TEST_CASE(create_rejects_null_empty_name) {
    EXPECT_NULL(xshm_create(NULL, 64));
    EXPECT_NULL(xshm_create("", 64));
}

TEST_CASE(create_rejects_zero_size) {
    EXPECT_NULL(xshm_create("/osxrdp_test_zero", 0));
}

TEST_CASE(create_rejects_overlong_name) {
    char name[300];
    memset(name, 'a', sizeof(name) - 1);
    name[0] = '/';
    name[sizeof(name) - 1] = '\0';
    /* name length 299 >= 260 */
    EXPECT_NULL(xshm_create(name, 64));
    EXPECT_NULL(xshm_open(name));
}

TEST_CASE(create_open_roundtrip_short_name) {
    char name[64];
    snprintf(name, sizeof(name), "/osxrdp_ut_%d", (int)getpid());

    xshm_t* owner = xshm_create(name, 128);
    if (owner == NULL) {
        /* Some environments may block shm_open; name-bound tests above still ran. */
        printf("    SKIP create/open roundtrip (xshm_create failed)\n");
        return;
    }

    EXPECT_NOT_NULL(owner->mem);
    EXPECT_EQ_INT((int)owner->size, 128);
    EXPECT_EQ_INT(owner->owner, 1);

    const char payload[] = "osxrdp";
    EXPECT_EQ_INT(xshm_write(owner, payload, (int)sizeof(payload)), 0);

    xshm_t* reader = xshm_open(name);
    EXPECT_NOT_NULL(reader);
    if (reader != NULL) {
        char buf[16] = {0};
        EXPECT_EQ_INT(xshm_read(reader, buf, (int)sizeof(payload)), 0);
        EXPECT_STREQ(buf, payload);
        xshm_close(reader);
        xshm_destroy(reader);
    }

    xshm_close(owner);
    xshm_destroy(owner);
}

int main(void) {
    printf("== test_xshm_name ==\n");
    RUN_TEST(create_rejects_null_empty_name);
    RUN_TEST(create_rejects_zero_size);
    RUN_TEST(create_rejects_overlong_name);
    RUN_TEST(create_open_roundtrip_short_name);
    return test_main_finish("test_xshm_name");
}
