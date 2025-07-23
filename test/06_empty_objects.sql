-- test/06_empty_objects.sql
\echo 'Test 6: Empty objects'
SELECT jsonb_merge('{}', '{"a": 1}') AS result_empty_first;
SELECT jsonb_merge('{}', '{"a": 1}') = '{"a": 1}' AS test_empty_first_passed;

SELECT jsonb_merge('{"a": 1}', '{}') AS result_empty_second;
SELECT jsonb_merge('{"a": 1}', '{}') = '{"a": 1}' AS test_empty_second_passed;

SELECT jsonb_merge('{}', '{}') AS result_both_empty;
SELECT jsonb_merge('{}', '{}') = '{}' AS test_both_empty_passed;
