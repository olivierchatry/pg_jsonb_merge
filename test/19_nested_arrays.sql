-- test/19_nested_arrays.sql
\echo 'Test 19: Nested arrays - arrays within objects within arrays'
SELECT jsonb_merge(
    '{"matrix": [[1, 2], [3, 4]], "config": {"items": [{"id": 1, "data": [1, 2]}]}}',
    '{"matrix": [[5, 6]], "config": {"items": [{"id": 2, "data": [3, 4]}]}}',
    true
) AS result;

SELECT jsonb_merge(
    '{"matrix": [[1, 2], [3, 4]], "config": {"items": [{"id": 1, "data": [1, 2]}]}}',
    '{"matrix": [[5, 6]], "config": {"items": [{"id": 2, "data": [3, 4]}]}}',
    true
) = '{"matrix": [[1, 2], [3, 4], [5, 6]], "config": {"items": [{"id": 1, "data": [1, 2]}, {"id": 2, "data": [3, 4]}]}}' AS test_passed;
