-- test/11_array_replace.sql
\echo 'Test 11: Array replace (merge_arrays = false)'
SELECT jsonb_merge('{"data": [1, 2, 3]}', '{"data": [4, 5, 6]}', false) AS result;

SELECT jsonb_merge('{"data": [1, 2, 3]}', '{"data": [4, 5, 6]}', false) = '{"data": [4, 5, 6]}' AS test_passed;
