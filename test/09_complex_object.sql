--- Test 9: Complex object with multiple levels and types
\echo 'Test 9: Complex object with multiple levels and types'
WITH actual AS (
    SELECT jsonb_merge(
        '{"a": 1, "b": {"c": [1, 2], "d": {"e": "hello"}}, "f": false}',
        '{"b": {"c": [3, 4], "d": {"g": "world"}}, "f": true, "h": null}',
        true
    ) AS result
),
expected AS (
    SELECT '{"a": 1, "b": {"c": [1, 2, 3, 4], "d": {"e": "hello", "g": "world"}}, "f": true, "h": null}'::jsonb AS result
)
SELECT a.result = e.result AS test_passed
FROM actual a, expected e;
