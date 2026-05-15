# Performance Benchmarks

> Tested on AMD Ryzen 7 9800X3D · 47 GiB RAM · WSL2 · PostgreSQL 17 in Docker  
> All data is randomized per row. Results use `sum(pg_column_size(...))` to force the optimizer to evaluate every merge.

## TL;DR

| What you need             | Best method                    | Why                                        |
| ------------------------- | ------------------------------ | ------------------------------------------ |
| Shallow merge (flat keys) | `\|\|` or `jsonb_merge()`      | Both fast; C ext ~11x faster than PL/pgSQL |
| Deep recursive merge      | `jsonb_merge()`                | **7–25x faster** than PL/pgSQL             |
| Array concatenation       | `jsonb_merge(..., true)`       | Only method that concatenates arrays       |
| Key-based array merge     | `jsonb_merge(..., true, 'id')` | Unique to this extension                   |

---

## Methods Under Test

### PL/pgSQL Deep Merge

A recursive function commonly recommended on blogs/Stack Overflow for deep JSONB merging:

```sql
CREATE FUNCTION jsonb_deep_merge_sql(a jsonb, b jsonb) RETURNS jsonb AS $$
DECLARE
    result jsonb := a;
    key text;
    val jsonb;
BEGIN
    FOR key, val IN SELECT * FROM jsonb_each(b) LOOP
        IF result ? key
           AND jsonb_typeof(result->key) = 'object'
           AND jsonb_typeof(val) = 'object' THEN
            result := jsonb_set(result, ARRAY[key],
                        jsonb_deep_merge_sql(result->key, val));
        ELSE
            result := jsonb_set(result, ARRAY[key], val);
        END IF;
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

**Why it's slow**: Each `jsonb_set()` copies the _entire_ document to update one key. For an object with N keys at depth D, this means `O(N × D)` full copies of the growing result.

### CTE SQL (Shallow Only)

The common Stack Overflow "merge two JSONB" pattern:

```sql
WITH all_keys AS (
    SELECT id, key, value FROM t, jsonb_each(json1)
    UNION
    SELECT id, key, value FROM t, jsonb_each(json2)
)
SELECT id, json_object_agg(key, value) FROM all_keys GROUP BY id;
```

**Why it's slow**: Decomposes every row into key-value rows (`jsonb_each`), sorts/deduplicates (`UNION`), then reaggregates (`json_object_agg`). For 1M rows × 3 keys = 6M intermediate rows. **Does not recurse** — nested objects are overwritten.

### `jsonb_merge()` (This Extension)

C extension that walks both JSONB binary trees in a single pass, building the merged result directly without intermediate copies or row explosion.

### `||` Operator (Built-in)

PostgreSQL's native shallow merge. Fast, but **overwrites nested objects** and **replaces arrays**.

---

## Scaling Results

Each benchmark runs `SELECT sum(pg_column_size(merged)) FROM (SELECT jsonb_merge(json1, json2) ...) sub` over the full table.

### Flat Objects

**Data**: 3 keys each (`{"a": i, "b": i*2, "shared": "..."}` vs `{"c": i*3, "d": i*4, "shared": "..."}`). ~66 bytes per document.

| Rows |  CTE SQL | PL/pgSQL | `jsonb_merge()` |  `\|\|` |
| ---: | -------: | -------: | --------------: | ------: |
|  100 |   3.2 ms |   2.0 ms |          0.9 ms |  0.8 ms |
|   1K |   6.2 ms |   6.2 ms |      **1.2 ms** |  1.2 ms |
|  10K |  69.9 ms |  40.0 ms |      **4.2 ms** |  4.9 ms |
| 100K |   546 ms |   389 ms |     **35.4 ms** | 44.2 ms |
|   1M | 5,139 ms | 3,940 ms |      **358 ms** |  153 ms |

`jsonb_merge()` is **11x faster** than PL/pgSQL at 1M rows — even for flat objects where the PL/pgSQL function only loops 3 keys.

### 3-Level Nested Objects

**Data**: `config.database.pool`, `config.cache`, `config.logging` with unique ports, TTLs, and pool sizes per row. ~330 + ~360 bytes per document pair.

| Rows |  PL/pgSQL | `jsonb_merge()` | Speedup |
| ---: | --------: | --------------: | ------: |
|  100 |    6.6 ms |      **1.3 ms** |      5x |
|   1K |   47.2 ms |      **3.0 ms** |     16x |
|  10K |    489 ms |     **20.4 ms** |     24x |
| 100K |  4,544 ms |      **207 ms** |     22x |
|   1M | 45,328 ms |    **1,749 ms** | **26x** |

### 4+ Level Real-World Config

**Data**: `app.features.notifications.push`, `db.primary.credentials`, `api.rate_limit` with unique hosts, pool sizes, and rate limits. ~650 + ~390 bytes per document pair.

| Rows |  PL/pgSQL | `jsonb_merge()` | Speedup |
| ---: | --------: | --------------: | ------: |
|  100 |    8.7 ms |      **1.3 ms** |      7x |
|   1K |   81.1 ms |      **3.9 ms** |     21x |
|  10K |    785 ms |     **29.5 ms** |     27x |
| 100K |  7,580 ms |      **291 ms** |     26x |
|   1M | 63,619 ms |    **2,542 ms** | **25x** |

### Heavy Objects — Fully Randomized

**Data**: User profiles with `user.preferences.notifications`, `metrics.sessions`, `permissions.scopes`, `metadata.extra`. 20+ keys, 3 nesting levels. Every field uses `md5(random()::text)` — no two rows share any value. ~1,800 + ~1,440 bytes per document pair.

| Rows |   PL/pgSQL | `jsonb_merge()` |  Speedup |
| ---: | ---------: | --------------: | -------: |
|  100 |    15.3 ms |      **2.5 ms** |       6x |
|   1K |     146 ms |     **21.3 ms** |       7x |
|  10K |   1,350 ms |      **156 ms** |       9x |
| 100K |  13,886 ms |    **1,487 ms** |       9x |
|   1M | 114,585 ms |   **15,248 ms** | **7.5x** |

### Arrays

**Data**: Objects with `tags` (3 strings), `scores` (3 ints), `meta.items` (3 ints). ~120 bytes per document.

| Rows | `jsonb_merge(true)` | `jsonb_merge(false)` |  `\|\|` |
| ---: | ------------------: | -------------------: | ------: |
|  100 |              1.1 ms |               1.0 ms |  0.9 ms |
|   1K |              2.1 ms |               1.8 ms |  1.6 ms |
|  10K |             10.1 ms |               9.8 ms |  9.2 ms |
| 100K |             85.7 ms |              85.5 ms | 81.5 ms |
|   1M |              879 ms |               854 ms |  282 ms |

`jsonb_merge(true)` concatenates arrays (unique capability). `jsonb_merge(false)` replaces them like `||`, but still deep-merges nested objects.

---

## Methods at a Glance

| Method            | Deep merge | Array concat | Key-based array merge | Speed (1M rows, 4-level) |
| ----------------- | :--------: | :----------: | :-------------------: | :----------------------: |
| `jsonb_merge()`   |     ✅     |      ✅      |          ✅           |        **2.5 s**         |
| `\|\|` operator   |     ❌     |      ❌      |          ❌           |  ~0.15 s (shallow only)  |
| PL/pgSQL function |     ✅     |      ❌      |          ❌           | 63.6 s (**25x slower**)  |
| CTE SQL           |     ❌     |      ❌      |          ❌           |  10.8 s (shallow only)   |

---

## Scalar Benchmarks

Single-call performance of `jsonb_merge()` in a PL/pgSQL loop (constant inputs, no table overhead):

| Operation                  | Iterations |   Total | Per call |
| -------------------------- | ---------: | ------: | -------: |
| Simple merge (2 keys each) |         1M | 22.9 ms | 0.023 µs |
| Deep merge (5 levels)      |       100K |  3.5 ms | 0.035 µs |
| Wide merge (20 keys each)  |        50K |  2.3 ms | 0.045 µs |
| Array concatenation        |       100K |  3.1 ms | 0.031 µs |
| Complex mixed structures   |        10K |  1.0 ms | 0.104 µs |

---

## Running Benchmarks

```bash
# Full benchmark suite (~9 min, outputs CSV to benchmark_results.csv)
./scripts/benchmark.sh

# Unit tests (includes basic perf checks)
./test/docker-test.sh
```
