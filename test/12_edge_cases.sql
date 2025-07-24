-- test/12_edge_cases.sql
\echo 'Test 12: Edge cases - very deep nesting'
SELECT jsonb_merge(
    '{"level1": {"level2": {"level3": {"level4": {"value": "deep"}}}}}',
    '{"level1": {"level2": {"level3": {"level4": {"new_value": "merged"}}}}}'
) AS result;

SELECT jsonb_merge(
    '{"level1": {"level2": {"level3": {"level4": {"value": "deep"}}}}}',
    '{"level1": {"level2": {"level3": {"level4": {"new_value": "merged"}}}}}'
) = '{"level1": {"level2": {"level3": {"level4": {"value": "deep", "new_value": "merged"}}}}}' AS test_passed;
