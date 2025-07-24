-- test/04_mixed_types.sql
\echo 'Test 4: Mixed types (non-object should override)'
SELECT jsonb_merge(
    '{"data": {"nested": {"value": 42}}}',
    '{"data": "simple string"}'
) AS result;

SELECT jsonb_merge(
    '{"data": {"nested": {"value": 42}}}',
    '{"data": "simple string"}'
) = '{"data": "simple string"}' AS test_passed;
