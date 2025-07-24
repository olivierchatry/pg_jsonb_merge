-- test/17_boolean_handling.sql
\echo 'Test 17: Boolean handling - true, false combinations'
SELECT jsonb_merge(
    '{"flag1": true, "flag2": false, "status": true}',
    '{"flag1": false, "flag3": true, "status": false}'
) AS result;

SELECT jsonb_merge(
    '{"flag1": true, "flag2": false, "status": true}',
    '{"flag1": false, "flag3": true, "status": false}'
) = '{"flag1": false, "flag2": false, "status": false, "flag3": true}' AS test_passed;
