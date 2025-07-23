-- test/01_basic_merge.sql
\echo 'Test 1: Basic merge'
SELECT jsonb_merge(
    '{"a": 1, "b": 2}',
    '{"c": 3, "b": 4}'
) AS result;

-- Verify the result
SELECT jsonb_merge(
    '{"a": 1, "b": 2}',
    '{"c": 3, "b": 4}'
) = '{"a": 1, "b": 4, "c": 3}' AS test_passed;
