# jsonb_merge (PostgreSQL extension)

`jsonb_merge(jsonb, jsonb [, boolean]) -> jsonb`

Recursive JSONB merge with optional array concatenation. Written in C.

## Behavior

Rules:

1. Objects are merged recursively.
2. If a key exists in both and both values are objects, merge them; otherwise the second value wins.
3. Keys present in only one input are kept.
4. Arrays: default call (`jsonb_merge(a,b)`) concatenates arrays. Use the 3‑arg form with `false` to replace instead of concatenate.
5. Scalars / non-objects at a position: if one side is not an object, that side just overwrites (second wins at the top level unless only the first is an object).
6. NULL handling: `jsonb_merge(NULL,x)=x`, `jsonb_merge(x,NULL)=x`, `jsonb_merge(NULL,NULL)=NULL`.

This differs from the built‑in `||` operator which is shallow (no deep merge, arrays always replaced).

## Functions

* `jsonb_merge(a jsonb, b jsonb)` – recursive merge, arrays concatenated.
* `jsonb_merge(a jsonb, b jsonb, merge_arrays boolean)` – set array policy explicitly.
Both are `IMMUTABLE`.

## Build & Install

Prerequisites: PostgreSQL dev headers (`pg_config`), `make`. Optional: Docker for isolated tests.

```bash
make            # build
make install    # install into PG
make clean      # remove artifacts
```

In psql:
 
```sql
CREATE EXTENSION jsonb_merge;
```

## Quick Examples

Basic:
 
```sql
SELECT jsonb_merge('{"a":1,"b":2}', '{"b":4,"c":3}');
-- {"a":1,"b":4,"c":3}
```

Deep:
 
```sql
SELECT jsonb_merge('{"user":{"name":"John","age":30}}', '{"user":{"age":31,"email":"john@example.com"}}');
-- {"user":{"name":"John","age":31,"email":"john@example.com"}}
```

Array concat (default):
 
```sql
SELECT jsonb_merge('{"a":[1,2]}', '{"a":[3,4]}');
-- {"a":[1,2,3,4]}
```

Array replace:
 
```sql
SELECT jsonb_merge('{"a":[1,2]}', '{"a":[3,4]}', false);
-- {"a":[3,4]}
```

## Testing

```bash
make test-docker         # run test suite in container
./test/docker-test.sh    # alt entrypoint
```

## Benchmarks

See `docs/BENCHMARKS.md`. Includes comparison vs `||` and deep / array cases.

## License

MIT (see `LICENSE`).
