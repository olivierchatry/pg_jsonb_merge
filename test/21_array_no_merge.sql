-- test/21_array_no_merge.sql
\echo 'Test 21: Array no merge - complex arrays with merge_arrays = false'
SELECT jsonb_merge(
    '{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}], "settings": {"theme": "dark"}}',
    '{"users": [{"id": 3, "name": "Charlie"}], "settings": {"language": "en"}}',
    false
) AS result;

SELECT jsonb_merge(
    '{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}], "settings": {"theme": "dark"}}',
    '{"users": [{"id": 3, "name": "Charlie"}], "settings": {"language": "en"}}',
    false
) = '{"users": [{"id": 3, "name": "Charlie"}], "settings": {"theme": "dark", "language": "en"}}' AS test_passed;
