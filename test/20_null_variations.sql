-- test/20_null_variations.sql
\echo 'Test 20: Null variations - explicit nulls in different contexts'
SELECT jsonb_merge(
    '{"explicit_null": null, "normal": "value", "nested": {"inner_null": null}}',
    '{"explicit_null": "overwritten", "new_null": null, "nested": {"new_field": "added"}}'
) AS result;

SELECT jsonb_merge(
    '{"explicit_null": null, "normal": "value", "nested": {"inner_null": null}}',
    '{"explicit_null": "overwritten", "new_null": null, "nested": {"new_field": "added"}}'
) = '{"explicit_null": "overwritten", "normal": "value", "nested": {"inner_null": null, "new_field": "added"}, "new_null": null}' AS test_passed;
