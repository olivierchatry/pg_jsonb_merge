# Performance Benchmarks

## Benchmark Results

Here are performance numbers from our test environment (Docker container with PostgreSQL 17):

### Simple Object Merge (1,000,000 iterations)
- **Operation**: `jsonb_merge('{"a": 1, "b": 2}', '{"c": 3, "d": 4}')`
- **Total**: 26.252 ms — **~0.000026 ms per operation**
- **Note**: On par with the built-in `||` operator for simple merges

### Deep Recursive Merge (100,000 iterations)
- **Operation**: `jsonb_merge('{"a": {"b": {"c": {"d": {"e": 1}}}}}', '{"a": {"b": {"c": {"d": {"f": 2}}}}}')`
- **Total**: 4.006 ms — **~0.000040 ms per operation**
- **Note**: Built-in `||` operator cannot perform deep recursive merging

### Large Object Merge (50,000 iterations)
- **Operation**: Merge two objects with 20 keys each (40 keys total)
- **Total**: 2.480 ms — **~0.000049 ms per operation**

### Array Merge (100,000 iterations)
- **Operation**: `jsonb_merge('{"data": [1,2,3,4,5]}', '{"data": [6,7,8,9,10]}', true)`
- **Total**: 3.378 ms — **~0.000033 ms per operation**
- **Note**: Built-in `||` operator replaces arrays, doesn't merge them

### Complex Mixed Structures (10,000 iterations)
- **Operation**: Merge objects with nested objects, arrays, and mixed types
- **Total**: 0.971 ms — **~0.000097 ms per operation**

## Performance Comparison: Scalar (500,000 iterations)

| Method | Total | Avg per operation |
|--------|------:|------------------:|
| `jsonb_merge()` extension | 13.634 ms | 0.000027 ms |
| Built-in `\|\|` operator | 13.216 ms | 0.000026 ms |

`jsonb_merge()` is essentially on par with the built-in `||` operator for simple shallow merges, while providing deep recursive merge capabilities that `||` cannot do.

## Performance Comparison: Table-based (100,000 rows)

### Recursive SQL merge approach

https://stackoverflow.com/questions/30101603/merging-concatenating-jsonb-columns-in-query

```sql
WITH all_json_key_value AS (
  SELECT id, t1.key, t1.value FROM test, jsonb_each(json1) AS t1
  UNION
  SELECT id, t1.key, t1.value FROM test, jsonb_each(json2) AS t1
)
SELECT id, json_object_agg(key, value)
FROM all_json_key_value
GROUP BY id
```

### Results

| Method | 100k rows | Avg per row |
|--------|----------:|------------:|
| Recursive SQL merge (CTE) | 559.886 ms | 0.005598 ms |
| `jsonb_merge()` extension | 5.530 ms | 0.000055 ms |
| Built-in `\|\|` operator | 5.470 ms | 0.000054 ms |

**`jsonb_merge()` is ~100x faster than the recursive SQL approach.**

The recursive SQL approach decomposes every row into individual key-value pairs via `jsonb_each`, unions them, and reaggregates with `json_object_agg` — resulting in massive overhead. `jsonb_merge()` operates directly on the binary JSONB representation, avoiding this cost entirely.

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
- **Container**: Alpine Linux with PostgreSQL 17
- **CPU**: Performance varies by host system
- **Memory**: Uses standard PostgreSQL memory management
- **Storage**: Container filesystem (performance may vary)

For production deployment, run benchmarks in your target environment to get accurate performance characteristics.
