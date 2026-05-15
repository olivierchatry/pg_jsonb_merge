# Performance Benchmarks

## Benchmark Results

Here are performance numbers from our test environment (Docker container with PostgreSQL 17):

### Simple Object Merge (1,000,000 iterations)
- **Operation**: `jsonb_merge('{"a": 1, "b": 2}', '{"c": 3, "d": 4}')`
- **Total**: 23.289 ms - **~0.000023 ms per operation**
- **Note**: On par with the built-in `||` operator for simple merges

### Deep Recursive Merge (100,000 iterations)
- **Operation**: `jsonb_merge('{"a": {"b": {"c": {"d": {"e": 1}}}}}', '{"a": {"b": {"c": {"d": {"f": 2}}}}}')`
- **Total**: 4.619 ms - **~0.000046 ms per operation**
- **Note**: Built-in `||` operator cannot perform deep recursive merging

### Large Object Merge (50,000 iterations)
- **Operation**: Merge two objects with 20 keys each (40 keys total)
- **Total**: 2.296 ms - **~0.000045 ms per operation**

### Array Merge (100,000 iterations)
- **Operation**: `jsonb_merge('{"data": [1,2,3,4,5]}', '{"data": [6,7,8,9,10]}', true)`
- **Total**: 3.453 ms - **~0.000034 ms per operation**
- **Note**: Built-in `||` operator replaces arrays, doesn't merge them

### Complex Mixed Structures (10,000 iterations)
- **Operation**: Merge objects with nested objects, arrays, and mixed types
- **Total**: 1.062 ms - **~0.000106 ms per operation**

## Performance Comparison: Scalar (500,000 iterations)

| Method | Total | Avg per operation |
|--------|------:|------------------:|
| `jsonb_merge()` extension | 11.964 ms | 0.000023 ms |
| Built-in `\|\|` operator | 12.789 ms | 0.000025 ms |

`jsonb_merge()` is essentially on par with the built-in `||` operator for simple shallow merges, while providing deep recursive merge capabilities that `||` cannot do.

---

## Scaling Benchmarks

All table-based benchmarks below measure total wall time for a single `SELECT` over the full table.

### Flat Object Merge (shallow keys)

Objects with 3 flat keys each (`a`, `b`, `shared` vs `c`, `d`, `shared`).

| Rows | CTE SQL merge | `jsonb_merge()` | `\|\|` operator |
|-----:|-------------:|----------------:|----------------:|
| 100 | 2.649 ms | **0.663 ms** | 1.247 ms |
| 1,000 | 5.552 ms | **1.032 ms** | 0.715 ms |
| 10,000 | 58.358 ms | **1.060 ms** | 1.104 ms |
| 100,000 | 506.361 ms | **4.614 ms** | 4.355 ms |
| 1,000,000 | 8,498.509 ms | **43.983 ms** | 22.382 ms |

> CTE SQL is **~100-200x slower** than `jsonb_merge()`. The gap widens at scale due to the row explosion from `jsonb_each` + `UNION`.

### 3-Level Nested Object Merge

Objects with `config.database.pool`, `config.cache`, `config.logging` structures.

| Rows | PL/pgSQL deep merge | `jsonb_merge()` | `\|\|` operator ⚠️ |
|-----:|-------------------:|----------------:|-------------------:|
| 100 | 0.778 ms | **0.735 ms** | 0.787 ms |
| 1,000 | 1.018 ms | **0.880 ms** | 0.825 ms |
| 10,000 | 1.902 ms | **1.633 ms** | 2.082 ms |
| 100,000 | 12.361 ms | **9.057 ms** | 8.640 ms |
| 1,000,000 | 208.288 ms | **118.863 ms** | 39.316 ms |

> `jsonb_merge()` is **~1.4-1.8x faster** than PL/pgSQL at scale. The `||` operator is fastest but **does not deep merge** (overwrites nested objects).

### 4+ Level Real-World Config Merge

Complex config objects with `app.features.notifications.push`, `db.primary.credentials`, `api.rate_limit` etc.

| Rows | PL/pgSQL deep merge | `jsonb_merge()` | `\|\|` operator ⚠️ |
|-----:|-------------------:|----------------:|-------------------:|
| 100 | 0.814 ms | **0.824 ms** | 0.852 ms |
| 1,000 | 1.131 ms | **0.851 ms** | 0.942 ms |
| 10,000 | 2.501 ms | **1.874 ms** | 1.988 ms |
| 100,000 | 14.342 ms | **11.414 ms** | 11.963 ms |
| 1,000,000 | 301.254 ms | **162.882 ms** | 78.702 ms |

> `jsonb_merge()` is **~1.3-1.9x faster** than PL/pgSQL for deep config merges. The advantage grows with row count.

### Array Merge

Objects with nested arrays (`tags`, `scores`, `meta.items`).

| Rows | `jsonb_merge(true)` | `jsonb_merge(false)` | `\|\|` operator |
|-----:|-------------------:|-----------:|----------------:|
| 100 | 0.943 ms | 1.971 ms | 0.963 ms |
| 1,000 | 0.832 ms | 0.729 ms | 0.767 ms |
| 10,000 | 1.421 ms | 1.290 ms | 1.408 ms |
| 100,000 | 7.157 ms | 6.227 ms | 6.582 ms |
| 1,000,000 | 102.713 ms | 60.573 ms | 24.340 ms |

> `jsonb_merge(true)` **concatenates arrays** (unique capability). `jsonb_merge(false)` replaces arrays like `||` but with deep object merging. The `||` operator replaces arrays and does no deep merge.

---

## Methods Compared

| Method | Deep merge | Array concat | Notes |
|--------|:----------:|:------------:|-------|
| `jsonb_merge()` C extension | ✅ | ✅ | This extension |
| `\|\|` operator | ❌ | ❌ | Built-in, shallow only |
| CTE SQL (`jsonb_each` + `UNION`) | ❌ | ❌ | Shallow key-level only, very slow |
| PL/pgSQL recursive function | ✅ | ❌ | Pure SQL, 1.3-1.9x slower |

## Running Benchmarks

### Integrated Benchmarks
Basic performance tests are included in the test suite:
```bash
./test/docker-test.sh
```
Look for "Test 22: Performance benchmarks" in the output.

### Detailed Benchmarks
For comprehensive benchmarking:
```bash
./benchmark.sh
```

### Custom Benchmarks
You can run custom benchmarks using the PostgreSQL container:
```bash
# Start container
docker compose up -d

# Install extension (done automatically by test script)
./test/docker-test.sh

# Run custom benchmark
docker exec jsonb_merge_test_db psql -U postgres -d postgres -c "
\timing on
DO \$\$
DECLARE 
    i integer; 
    result jsonb;
BEGIN
    FOR i IN 1..1000 LOOP
        result := jsonb_merge('YOUR_JSON_1', 'YOUR_JSON_2');
    END LOOP;
END \$\$;
"
```

## Performance Notes

1. **Optimization Focus**: The extension is optimized for correctness and recursive merging capability rather than raw speed
2. **Memory Efficiency**: Uses PostgreSQL's built-in JSONB structures for memory efficiency
3. **Competitive Performance**: Performs similarly to built-in operators for simple operations
4. **Unique Capabilities**: Provides functionality (deep recursive merge, array merging) not available in built-in operators
5. **Regression Testing**: Benchmark tests help catch performance regressions during development

## Benchmark Environment
- **Host OS**: Windows (WSL2) - Kernel 6.6.114.1-microsoft-standard-WSL2
- **CPU**: AMD Ryzen 7 9800X3D 8-Core Processor (16 threads)
- **RAM**: 47 GiB
- **Container**: Alpine Linux with PostgreSQL 17 (Docker)
- **Storage**: Container filesystem

For production deployment, run benchmarks in your target environment to get accurate performance characteristics.
