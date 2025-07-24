-- test/07_array_handling.sql
\echo 'Test 7: Array handling (arrays should be overwritten by default)'
SELECT jsonb_merge('{"data": [1, 2, 3]}', '{"data": [4, 5, 6]}', false) AS result;

SELECT jsonb_merge('{"data": [1, 2, 3]}', '{"data": [4, 5, 6]}', false) = '{"data": [4, 5, 6]}' AS test_passed;
