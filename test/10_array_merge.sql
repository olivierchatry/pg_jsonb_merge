-- test/10_array_merge.sql
\echo 'Test 10: Array merge'
SELECT jsonb_merge(
    '{"a": [1, 2], "b": 1}',
    '{"a": [3, 4], "c": 2}'
) AS result;

SELECT jsonb_merge(
    '{"a": [1, 2], "b": 1}',
    '{"a": [3, 4], "c": 2}'
) = '{"a": [1, 2, 3, 4], "b": 1, "c": 2}' AS test_passed;
