#include "harness.h"
#include "../ServerApp/OSXRDP/Clipboard/ClipProtocol.h"
#include <string.h>

TEST_CASE(test_safe_path_accepts_simple) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo") == true);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/bar") == true);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/bar/baz.txt") == true);
}

TEST_CASE(test_safe_path_rejects_absolute) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("/etc/passwd") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("/tmp") == false);
}

TEST_CASE(test_safe_path_rejects_dot_dot) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("..") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("../foo") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/..") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/../bar") == false);
}

TEST_CASE(test_safe_path_rejects_dot) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath(".") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("./foo") == false);
}

TEST_CASE(test_safe_path_rejects_empty) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath(NULL) == false);
}

TEST_CASE(test_safe_path_rejects_trailing_slash) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo/bar/") == false);
}

TEST_CASE(test_safe_path_rejects_backslash_absolute) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("\\Windows\\System32") == false);
}

TEST_CASE(test_safe_path_rejects_windows_drive) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("C:\\Windows") == false);
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("C:/Windows") == false);
}

TEST_CASE(test_safe_path_accepts_backslash_relative) {
    EXPECT_TRUE(ClipProtocol_IsSafeRelativePath("foo\\bar") == true);
}

TEST_CASE(test_write_uint64_roundtrip) {
    unsigned char buf[8];
    uint64_t val = 0xDEADBEEFCAFEBABEULL;
    ClipProtocol_WriteUInt64ToBuffer(buf, val);

    // Verify LE encoding
    EXPECT_EQ_INT((int)buf[0], 0xBE);
    EXPECT_EQ_INT((int)buf[1], 0xBA);
    EXPECT_EQ_INT((int)buf[2], 0xFE);
    EXPECT_EQ_INT((int)buf[3], 0xCA);
    EXPECT_EQ_INT((int)buf[4], 0xEF);
    EXPECT_EQ_INT((int)buf[5], 0xBE);
    EXPECT_EQ_INT((int)buf[6], 0xAD);
    EXPECT_EQ_INT((int)buf[7], 0xDE);
}

TEST_CASE(test_read_uint64_from_low_high) {
    uint64_t val = ClipProtocol_ReadUInt64FromLowHigh(0xCAFEBABE, 0xDEADBEEF);
    EXPECT_TRUE(val == 0xDEADBEEFCAFEBABEULL);
}

TEST_CASE(test_uint64_roundtrip_combined) {
    uint64_t original = 0x123456789ABCDEF0ULL;
    unsigned char buf[8];
    ClipProtocol_WriteUInt64ToBuffer(buf, original);

    uint32_t low = (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
                   ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
    uint32_t high = (uint32_t)buf[4] | ((uint32_t)buf[5] << 8) |
                    ((uint32_t)buf[6] << 16) | ((uint32_t)buf[7] << 24);
    uint64_t result = ClipProtocol_ReadUInt64FromLowHigh(low, high);
    EXPECT_TRUE(result == original);
}

TEST_CASE(test_format_priority_richtext) {
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_RICHTEXT, 0), 40);
}

TEST_CASE(test_format_priority_image) {
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_IMAGE, 0), 30);
}

TEST_CASE(test_format_priority_text_unicode) {
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_TEXT, CLIP_PROTOCOL_CF_UNICODETEXT), 20);
}

TEST_CASE(test_format_priority_text_other) {
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_TEXT, 1), 0);
}

TEST_CASE(test_format_priority_none) {
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_NONE, 0), 0);
    EXPECT_EQ_INT(ClipProtocol_GetRequestedFormatPriority(CLIP_PROTOCOL_TYPE_FILELIST, 0), 0);
}

int main(void) {
    RUN_TEST(test_safe_path_accepts_simple);
    RUN_TEST(test_safe_path_rejects_absolute);
    RUN_TEST(test_safe_path_rejects_dot_dot);
    RUN_TEST(test_safe_path_rejects_dot);
    RUN_TEST(test_safe_path_rejects_empty);
    RUN_TEST(test_safe_path_rejects_trailing_slash);
    RUN_TEST(test_safe_path_rejects_backslash_absolute);
    RUN_TEST(test_safe_path_rejects_windows_drive);
    RUN_TEST(test_safe_path_accepts_backslash_relative);
    RUN_TEST(test_write_uint64_roundtrip);
    RUN_TEST(test_read_uint64_from_low_high);
    RUN_TEST(test_uint64_roundtrip_combined);
    RUN_TEST(test_format_priority_richtext);
    RUN_TEST(test_format_priority_image);
    RUN_TEST(test_format_priority_text_unicode);
    RUN_TEST(test_format_priority_text_other);
    RUN_TEST(test_format_priority_none);
    return test_main_finish("test_clip_protocol");
}
