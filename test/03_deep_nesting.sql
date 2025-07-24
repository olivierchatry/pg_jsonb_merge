-- test/03_deep_nesting.sql
\echo 'Test 3: Deep nesting'
SELECT jsonb_merge(
    '{"config": {"database": {"host": "localhost", "port": 5432}, "cache": {"enabled": true}}}',
    '{"config": {"database": {"port": 5433, "ssl": true}, "logging": {"level": "info"}}}'
) AS result;

SELECT jsonb_merge(
    '{"config": {"database": {"host": "localhost", "port": 5432}, "cache": {"enabled": true}}}',
    '{"config": {"database": {"port": 5433, "ssl": true}, "logging": {"level": "info"}}}'
) = '{"config": {"database": {"host": "localhost", "port": 5433, "ssl": true}, "cache": {"enabled": true}, "logging": {"level": "info"}}}' AS test_passed;
