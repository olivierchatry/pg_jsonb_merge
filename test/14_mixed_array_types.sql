-- test/14_mixed_array_types.sql
\echo 'Test 14: Mixed array types - different data types in arrays'
SELECT jsonb_merge(
    '{"mixed": [1, "hello", true]}',
    '{"mixed": [null, {"nested": "object"}, [1, 2]]}',
    true
) AS result;

SELECT jsonb_merge(
    '{"mixed": [1, "hello", true]}',
    '{"mixed": [null, {"nested": "object"}, [1, 2]]}',
    true
) = '{"mixed": [1, "hello", true, null, {"nested": "object"}, [1, 2]]}' AS test_passed;
