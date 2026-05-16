# Release Notes for v1.3.0

## What's Changed (since v1.2.0)

### Features
- feat: add `jsonb_merge_with_key` support for merging arrays of objects by key (4ae2c78)
- feat: enhance benchmarks and add tests for array key merging in `jsonb_merge` (4c45c80)
- feat: update benchmarks and add scaling tests for `jsonb_merge` (8524e94)
- feat: update benchmark scripts to include CSV output and expand performance coverage (562ec83)

### Bug Fixes
- fix: formatting cleanup (fb94f82)

### Maintenance
- chore: remove artifact retention period from CI configuration (d76b9f9)

## PostgreSQL Compatibility
- [x] PostgreSQL 12
- [x] PostgreSQL 13
- [x] PostgreSQL 14
- [x] PostgreSQL 15
- [x] PostgreSQL 16
- [x] PostgreSQL 17
- [x] PostgreSQL 18

## Breaking Changes
- None

## Installation
Download the appropriate archive for your PostgreSQL version from the release assets.

## Verification
```sql
SELECT jsonb_merge(
  '{"items":[{"id":1,"v":10},{"id":2,"v":20}]}',
  '{"items":[{"id":2,"extra":true},{"id":3,"v":30}]}',
  true,
  'id'
);
-- Expected: {"items":[{"id":1,"v":10},{"id":2,"v":20,"extra":true},{"id":3,"v":30}]}
```