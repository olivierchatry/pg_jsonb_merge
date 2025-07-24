-- test/08_no_common_keys.sql
\echo 'Test 8: No common keys'
SELECT jsonb_merge(
    '{"a": 1, "b": 2}',
    '{"c": 3, "d": 4}'
) AS result;

SELECT jsonb_merge(
    '{"a": 1, "b": 2}',
    '{"c": 3, "d": 4}'
) = '{"a": 1, "b": 2, "c": 3, "d": 4}' AS test_passed;
