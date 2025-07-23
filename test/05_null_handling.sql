-- test/05_null_handling.sql
\echo 'Test 5: NULL handling'
SELECT jsonb_merge('{"a": 1}', NULL::jsonb) AS result_null_second;
SELECT jsonb_merge('{"a": 1}', NULL::jsonb) = '{"a": 1}' AS test_null_second_passed;

SELECT jsonb_merge(NULL::jsonb, '{"b": 2}') AS result_null_first;
SELECT jsonb_merge(NULL::jsonb, '{"b": 2}') = '{"b": 2}' AS test_null_first_passed;
