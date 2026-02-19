# Release Notes for v1.1.0

## What's Changed (since v1.0.0)

### Features
- feat: add support for version 1.1.0 with new SQL installation script and update Makefile (e829cab)
- feat: update default version to 1.1.0 in jsonb_merge control file (25e7bae)
- feat: enhance release notes generation with changelog categorization (0814d99)
- feat: update release notes to include PostgreSQL 18 compatibility (57be242)
- feat: enhance jsonb_merge performance benchmarks with increased iterations (0645c58)
- feat: add support for PostgreSQL 18 in CI workflows (8a40101)

### Maintenance
- merge: Merge branch 'main' of github.com:olivierchatry/pg_jsonb_merge (a482815)
- chore: update documentation (bd32d8f)

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
