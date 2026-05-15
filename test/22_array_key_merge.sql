-- Test cases for merging arrays of objects by a key.

\set ON_ERROR_STOP on
\echo 'Test 22: Array key merge - merge arrays of objects by matching key'

-- Test: Basic keyed merge
-- Objects with the same 'id' should be merged. New objects should be appended.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}, {"id": 2, "v": 20}]}',
  '{"items": [{"id": 2, "extra": true}, {"id": 3, "v": 30}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 10}, {"id": 2, "v": 20, "extra": true}, {"id": 3, "v": 30}]}' AS test_passed;

-- Test: Key not present in all objects
-- Objects without the specified key should be treated as distinct and not merged.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}, {"v": 99}]}',
  '{"items": [{"id": 1, "extra": true}, {"v": 98}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 10, "extra": true}, {"v": 99}, {"v": 98}]}' AS test_passed;

-- Test: No matching keys
-- If no keys match, the arrays should be concatenated.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}]}',
  '{"items": [{"id": 2, "v": 20}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 10}, {"id": 2, "v": 20}]}' AS test_passed;

-- Test: Nested merge within array objects
-- The recursive merge should apply to the contents of the matched objects.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "data": {"a": 1}}, {"id": 2, "data": {"b": 2}}]}',
  '{"items": [{"id": 1, "data": {"c": 3}}, {"id": 3, "data": {"d": 4}}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "data": {"a": 1, "c": 3}}, {"id": 2, "data": {"b": 2}}, {"id": 3, "data": {"d": 4}}]}' AS test_passed;

-- Test: Key value is not a scalar
-- Merging should only work for scalar key values (string, number, boolean, null). Non-scalar keys are not matched.
SELECT jsonb_merge(
  '{"items": [{"id": [1], "v": 10}]}',
  '{"items": [{"id": [1], "v": 20}]}',
  true,
  'id'
) = '{"items": [{"id": [1], "v": 10}, {"id": [1], "v": 20}]}' AS test_passed;

-- Test: Key present in one array but not the other
-- Objects are not merged if the key is missing.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}]}',
  '{"items": [{"name": "obj2", "v": 20}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 10}, {"name": "obj2", "v": 20}]}' AS test_passed;

-- Test: NULL value for key
-- NULLs are matched against other NULLs.
SELECT jsonb_merge(
  '{"items": [{"id": null, "v": 10}, {"id": 1, "v": 1}]}',
  '{"items": [{"id": null, "v": 20}, {"id": 2, "v": 2}]}',
  true,
  'id'
) = '{"items": [{"id": null, "v": 20}, {"id": 1, "v": 1}, {"id": 2, "v": 2}]}' AS test_passed;

-- Test: merge_arrays=false with a key provided
-- The key should be ignored and the array should be replaced.
SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}]}',
  '{"items": [{"id": 1, "v": 20}]}',
  false,
  'id'
) = '{"items": [{"id": 1, "v": 20}]}' AS test_passed;

-- Test: Different data types for key
-- '1' (string) and 1 (number) are different keys.
SELECT jsonb_merge(
  '{"items": [{"id": "1", "v": 10}]}',
  '{"items": [{"id": 1, "v": 20}]}',
  true,
  'id'
) = '{"items": [{"id": "1", "v": 10}, {"id": 1, "v": 20}]}' AS test_passed;

-- Test: Empty arrays
SELECT jsonb_merge(
  '{"items": []}',
  '{"items": [{"id": 1, "v": 20}]}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 20}]}' AS test_passed;

SELECT jsonb_merge(
  '{"items": [{"id": 1, "v": 10}]}',
  '{"items": []}',
  true,
  'id'
) = '{"items": [{"id": 1, "v": 10}]}' AS test_passed;
