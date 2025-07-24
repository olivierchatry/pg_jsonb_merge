-- Test: Array handling with merge_arrays = false (default behavior)
WITH actual AS (
    SELECT jsonb_merge('{"data": [1, 2, 3]}', '{"data": [4, 5, 6]}', false) AS result
),
expected AS (
    SELECT '{"data": [4, 5, 6]}'::jsonb AS result
)
SELECT a.result = e.result AS test_passed
FROM actual a, expected e;
