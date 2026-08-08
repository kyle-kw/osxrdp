#include "harness.h"
#include "xstream.h"

#include <string.h>

TEST_CASE(create_rejects_non_positive_size) {
    EXPECT_NULL(xstream_create(0));
    EXPECT_NULL(xstream_create(-1));
}

TEST_CASE(write_read_int32_roundtrip) {
    xstream_t* s = xstream_create(64);
    EXPECT_NOT_NULL(s);
    EXPECT_EQ_INT(xstream_writeInt32(s, 0x12345678), 0);
    EXPECT_EQ_INT(xstream_writeInt32(s, -7), 0);

    xstream_resetPos(s);
    EXPECT_EQ_INT(xstream_readInt32(s), 0x12345678);
    EXPECT_EQ_INT(xstream_readInt32(s), -7);
    xstream_free(s);
}

TEST_CASE(write_overflow_fails) {
    xstream_t* s = xstream_create(4);
    EXPECT_NOT_NULL(s);
    EXPECT_EQ_INT(xstream_writeInt32(s, 1), 0);
    EXPECT_EQ_INT(xstream_writeInt32(s, 2), 1);
    xstream_free(s);
}

TEST_CASE(str_roundtrip) {
    xstream_t* s = xstream_create(128);
    EXPECT_NOT_NULL(s);
    const char* msg = "hello";
    EXPECT_EQ_INT(xstream_writeStr(s, msg, (int)strlen(msg)), 0);

    int rawLen = 0;
    const void* raw = xstream_get_raw_buffer(s, &rawLen);
    EXPECT_NOT_NULL(raw);
    EXPECT_TRUE(rawLen > 0);

    xstream_t* r = xstream_create_for_read((void*)raw, rawLen);
    EXPECT_NOT_NULL(r);
    int outLen = 0;
    const char* out = xstream_readStr(r, &outLen);
    EXPECT_NOT_NULL(out);
    EXPECT_EQ_INT(outLen, (int)strlen(msg));
    EXPECT_STREQ(out, msg);
    xstream_free(r);
    xstream_free(s);
}

TEST_CASE(read_str_requires_nul_terminator) {
    /* layout: int32 len=5, then "hello" without trailing NUL */
    unsigned char buf[4 + 5];
    int len = 5;
    memcpy(buf, &len, sizeof(int));
    memcpy(buf + 4, "hello", 5);

    xstream_t* r = xstream_create_for_read(buf, (int)sizeof(buf));
    EXPECT_NOT_NULL(r);
    EXPECT_NULL(xstream_readStr(r, NULL));
    xstream_free(r);
}

TEST_CASE(read_str_accepts_nul_terminator) {
    unsigned char buf[4 + 6];
    int len = 5;
    memcpy(buf, &len, sizeof(int));
    memcpy(buf + 4, "hello", 6); /* includes '\0' */

    xstream_t* r = xstream_create_for_read(buf, (int)sizeof(buf));
    EXPECT_NOT_NULL(r);
    int outLen = 0;
    const char* out = xstream_readStr(r, &outLen);
    EXPECT_NOT_NULL(out);
    EXPECT_EQ_INT(outLen, 5);
    EXPECT_STREQ(out, "hello");
    xstream_free(r);
}

TEST_CASE(create_for_read_rejects_bad_args) {
    char data[4] = {0};
    EXPECT_NULL(xstream_create_for_read(NULL, 4));
    EXPECT_NULL(xstream_create_for_read(data, 0));
}

TEST_CASE(position_and_checked_patch) {
    xstream_t* s = xstream_create(16);
    EXPECT_NOT_NULL(s);
    EXPECT_EQ_INT(xstream_getPosition(s), 0);
    EXPECT_EQ_INT(xstream_writeInt32(s, 0), 0);
    EXPECT_EQ_INT(xstream_writeInt32(s, 9), 0);
    EXPECT_EQ_INT(xstream_getPosition(s), 8);
    EXPECT_EQ_INT(xstream_patchInt32(s, 0, 7), 0);
    EXPECT_EQ_INT(xstream_patchInt32(s, 6, 1), 1);
    xstream_resetPos(s);
    EXPECT_EQ_INT(xstream_readInt32(s), 7);
    EXPECT_EQ_INT(xstream_readInt32(s), 9);
    xstream_free(s);
}

int main(void) {
    printf("== test_xstream ==\n");
    RUN_TEST(create_rejects_non_positive_size);
    RUN_TEST(write_read_int32_roundtrip);
    RUN_TEST(write_overflow_fails);
    RUN_TEST(str_roundtrip);
    RUN_TEST(read_str_requires_nul_terminator);
    RUN_TEST(read_str_accepts_nul_terminator);
    RUN_TEST(create_for_read_rejects_bad_args);
    RUN_TEST(position_and_checked_patch);
    return test_main_finish("test_xstream");
}
