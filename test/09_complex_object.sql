-- test/09_complex_object.sql
\echo 'Test 9: Complex object with multiple levels and types'
SELECT jsonb_merge(
    '{
        "a": 1,
        "b": {
            "c": [1, 2],
            "d": {"e": "hello"}
        },
        "f": true
    }',
    '{
        "b": {
            "c": [3, 4],
            "d": {"g": "world"}
        },
        "h": null
    }'
) AS result;

-- Verify the result
SELECT jsonb_merge(
    '{
        "a": 1,
        "b": {
            "c": [1, 2],
            "d": {"e": "hello"}
        },
        "f": true
    }',
    '{
        "b": {
            "c": [3, 4],
            "d": {"g": "world"}
        },
        "h": null
    }'
) = '{
    "a": 1,
    "b": {
        "c": [3, 4],
        "d": {"e": "hello", "g": "world"}
    },
    "f": true,
    "h": null
}' AS test_passed;
