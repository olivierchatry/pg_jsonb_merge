-- test/07_array_handling.sql
\echo 'Test 7: Array handling (arrays should be overwritten)'
SELECT jsonb_merge(
    '{"data": [1, 2, 3]}',
    '{"data": [4, 5, 6]}'
) AS result;

-- Verify the result
SELECT jsonb_merge(
    '{"data": [1, 2, 3]}',
    '{"data": [4, 5, 6]}'
) = '{"data": [4, 5, 6]}' AS test_passed;
