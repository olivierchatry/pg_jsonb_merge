# Performance Benchmarks

## Benchmark Results

Here are typical performance numbers from our test environment (Docker container with PostgreSQL 17):

### Simple Object Merge
- **Operation**: `jsonb_merge('{"a": 1, "b": 2}', '{"c": 3, "d": 4}')`
- **Performance**: ~0.0002 ms per operation (1000 iterations: 0.200 ms)
- **Comparison**: Built-in `||` operator: ~0.0003 ms per operation
- **Note**: Our extension is competitive with built-in operator for simple merges

### Deep Recursive Merge
- **Operation**: `jsonb_merge('{"a": {"b": {"c": {"d": 1}}}}', '{"a": {"b": {"c": {"e": 2}}}}')`
- **Performance**: ~0.0016 ms per operation (100 iterations: 0.159 ms)
- **Note**: Built-in `||` operator cannot perform deep recursive merging

### Array Merge
- **Operation**: `jsonb_merge('{"data": [1,2,3,4,5]}', '{"data": [6,7,8,9,10]}', true)`
- **Performance**: ~0.0016 ms per operation (100 iterations: 0.157 ms)
- **Note**: Built-in `||` operator replaces arrays, doesn't merge them

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
docker-compose up -d

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
