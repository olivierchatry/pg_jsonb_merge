-- test/02_recursive_merge.sql
\echo 'Test 2: Recursive merge'
SELECT jsonb_merge(
    '{"user": {"name": "John", "age": 30}, "status": "active"}',
    '{"user": {"age": 31, "email": "john@example.com"}, "last_login": "2024-01-01"}'
) AS result;

SELECT jsonb_merge(
    '{"user": {"name": "John", "age": 30}, "status": "active"}',
    '{"user": {"age": 31, "email": "john@example.com"}, "last_login": "2024-01-01"}'
) = '{"user": {"name": "John", "age": 31, "email": "john@example.com"}, "status": "active", "last_login": "2024-01-01"}' AS test_passed;
