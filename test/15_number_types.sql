-- test/15_number_types.sql
\echo 'Test 15: Different number types - integers, floats, scientific notation'
SELECT jsonb_merge(
    '{"int": 42, "float": 3.14, "scientific": 1.5e2}',
    '{"int": 100, "negative": -25, "zero": 0}'
) AS result;

SELECT jsonb_merge(
    '{"int": 42, "float": 3.14, "scientific": 1.5e2}',
    '{"int": 100, "negative": -25, "zero": 0}'
) = '{"int": 100, "float": 3.14, "scientific": 150, "negative": -25, "zero": 0}' AS test_passed;
