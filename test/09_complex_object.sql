-- test/09_complex_object.sql
\echo 'Test 9: Complex object with multiple levels and types'
SELECT jsonb_merge(
    '{"a": 1, "b": {"c": [1, 2], "d": {"e": "hello"}}, "f": false}',
    '{"b": {"c": [3, 4], "d": {"g": "world"}}, "f": true, "h": null}',
    true
) AS result;

SELECT jsonb_merge(
    '{"a": 1, "b": {"c": [1, 2], "d": {"e": "hello"}}, "f": false}',
    '{"b": {"c": [3, 4], "d": {"g": "world"}}, "f": true, "h": null}',
    true
) = '{"a": 1, "b": {"c": [1, 2, 3, 4], "d": {"e": "hello", "g": "world"}}, "f": true, "h": null}' AS test_passed;
