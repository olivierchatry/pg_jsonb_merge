# Release Notes for v1.2.0

## What's Changed (since v1.1.0)

### Features
- feat: add support for PostgreSQL 18 in CI/CD pipeline and update release notes (f592508)

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
SELECT jsonb_merge('{"a": 1}', '{"b": 2}');
-- Expected: {"a": 1, "b": 2}
```
