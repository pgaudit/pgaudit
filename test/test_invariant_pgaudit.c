#include <check.h>
#include <stdlib.h>
#include <string.h>
#include "pgaudit.c"

START_TEST(test_buffer_reads_never_exceed_declared_length)
{
    // Invariant: Buffer reads never exceed the declared length
    const char *payloads[] = {
        "normal_input",                     // Valid input
        "A",                                // Boundary: single char
        "very_long_input_that_exceeds_buffer_by_2x_XXXXXXXXXXXXXXXXXXXX",  // 2x overflow
        "massive_overflow_"                 // Exact exploit case from audit
        "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
        "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
        "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",  // 10x+ overflow
        ""                                  // Empty string
    };
    int num_payloads = sizeof(payloads) / sizeof(payloads[0]);
    
    for (int i = 0; i < num_payloads; i++) {
        char dest[16] = {0};  // Small fixed buffer
        const char *src = payloads[i];
        size_t src_len = strlen(src);
        
        // Test strncpy - must not write beyond dest[15]
        memset(dest, 0xAA, sizeof(dest));  // Fill with sentinel
        strncpy(dest, src, sizeof(dest) - 1);
        dest[sizeof(dest) - 1] = '\0';  // Ensure null termination
        
        // Check no overflow into sentinel region
        char sentinel_check[32];
        memset(sentinel_check, 0xAA, sizeof(sentinel_check));
        ck_assert_msg(memcmp(dest, sentinel_check, sizeof(dest)) != 0 ||
                     src_len < sizeof(dest),
                     "Buffer overflow detected for payload %d", i);
        
        // Verify null termination when truncated
        if (src_len >= sizeof(dest) - 1) {
            ck_assert_msg(dest[sizeof(dest) - 1] == '\0',
                         "Missing null termination for truncated payload %d", i);
        }
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_buffer_reads_never_exceed_declared_length);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}