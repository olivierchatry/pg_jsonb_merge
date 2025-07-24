-- test/16_string_edge_cases.sql
\echo 'Test 16: String edge cases - empty strings, special characters'
SELECT jsonb_merge(
    '{"empty": "", "special": "hello\nworld\ttab", "unicode": "café"}',
    '{"empty": "not empty", "quotes": "He said \"hello\"", "backslash": "path\\to\\file"}'
) AS result;

SELECT jsonb_merge(
    '{"empty": "", "special": "hello\nworld\ttab", "unicode": "café"}',
    '{"empty": "not empty", "quotes": "He said \"hello\"", "backslash": "path\\to\\file"}'
) = '{"empty": "not empty", "special": "hello\nworld\ttab", "unicode": "café", "quotes": "He said \"hello\"", "backslash": "path\\to\\file"}' AS test_passed;
