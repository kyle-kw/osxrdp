#ifndef OSXRDP_TEST_HARNESS_H
#define OSXRDP_TEST_HARNESS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_test_failures = 0;
static int g_test_count = 0;
static int g_test_skips = 0;

#define TEST_CASE(name) \
    static void name(void); \
    static void name##_run(void) { \
        g_test_count++; \
        printf("  RUN  %s\n", #name); \
        name(); \
    } \
    static void name(void)

#define EXPECT_TRUE(expr) \
    do { \
        if (!(expr)) { \
            fprintf(stderr, "    FAIL %s:%d: EXPECT_TRUE(%s)\n", __FILE__, __LINE__, #expr); \
            g_test_failures++; \
        } \
    } while (0)

#define EXPECT_EQ_INT(a, b) \
    do { \
        const int _a = (int)(a); \
        const int _b = (int)(b); \
        if (_a != _b) { \
            fprintf(stderr, "    FAIL %s:%d: EXPECT_EQ_INT(%s, %s) got %d vs %d\n", \
                    __FILE__, __LINE__, #a, #b, _a, _b); \
            g_test_failures++; \
        } \
    } while (0)

#define EXPECT_STREQ(a, b) \
    do { \
        const char* _a = (a); \
        const char* _b = (b); \
        if (_a == NULL || _b == NULL || strcmp(_a, _b) != 0) { \
            fprintf(stderr, "    FAIL %s:%d: EXPECT_STREQ(%s, %s) got \"%s\" vs \"%s\"\n", \
                    __FILE__, __LINE__, #a, #b, \
                    _a ? _a : "(null)", _b ? _b : "(null)"); \
            g_test_failures++; \
        } \
    } while (0)

#define EXPECT_NULL(ptr) EXPECT_TRUE((ptr) == NULL)
#define EXPECT_NOT_NULL(ptr) EXPECT_TRUE((ptr) != NULL)

#define RUN_TEST(fn) fn##_run()

#define SKIP_TEST(reason) \
    do { \
        g_test_skips++; \
        printf("    SKIP %s\n", (reason)); \
        return; \
    } while (0)

static int test_main_finish(const char* suite) {
    if (g_test_failures == 0) {
        if (g_test_skips > 0 && getenv("CI") != NULL) {
            printf("FAIL %s (%d skipped tests are not allowed in CI)\n", suite, g_test_skips);
            return 1;
        }
        if (g_test_skips > 0) {
            printf("OK  %s (%d tests; passed with %d skips)\n", suite, g_test_count, g_test_skips);
            return 0;
        }
        printf("OK  %s (%d tests)\n", suite, g_test_count);
        return 0;
    }
    printf("FAIL %s (%d failures / %d tests)\n", suite, g_test_failures, g_test_count);
    return 1;
}

#endif /* OSXRDP_TEST_HARNESS_H */
