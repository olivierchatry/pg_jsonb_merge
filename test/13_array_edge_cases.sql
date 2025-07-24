-- test/13_array_edge_cases.sql
\echo 'Test 13: Array edge cases - empty arrays'
SELECT jsonb_merge(
    '{"data": []}',
    '{"data": [1, 2, 3]}',
    true
) AS result;

SELECT jsonb_merge(
    '{"data": []}',
    '{"data": [1, 2, 3]}',
    true
) = '{"data": [1, 2, 3]}' AS test_passed;
