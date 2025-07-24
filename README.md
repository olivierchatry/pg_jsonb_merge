# PostgreSQL JSONB Merge Extension

This PostgreSQL extension provides a C function `jsonb_merge(jsonb, jsonb)` that recursively merges two JSONB objects.

## Merge Logic

The `jsonb_merge` function follows these rules:

- **Objects are merged recursively**: If a key is present in both JSONB objects and both values are objects, the function will recursively merge them.
- **Conflicts are resolved by the second object**: If a key exists in both objects and the values are not both objects, the value from the second object will be used.
- **Keys from both objects are preserved**: If a key is present in only one of the objects, it will be included in the final result.
- **Arrays and other types are overwritten**: The merge logic is designed for objects. If the values are arrays, strings, numbers, etc., the value from the second object will replace the value from the first.

## Features

- **Recursive Merge**: Deeply merges nested JSONB objects.
- **Configurable Array Merge**: Choose to merge or replace arrays with boolean flag.
- **C Implementation**: High-performance merge logic written in C.
- **Debug and Release Builds**: `Makefile` supports both debug and release build modes.
- **Dockerized Testing**: Includes a Docker setup for isolated testing.
- **Performance Benchmarks**: Built-in benchmarking for regression testing.
- **Cross-Platform**: Builds on macOS and Linux.

## Getting Started

### Prerequisites

- PostgreSQL (with `pg_config`)
- Docker (for containerized testing)
- `make`

### Build

```bash
# Build the extension
make all

# Clean build artifacts
make clean

# Install the extension (requires PostgreSQL development headers)
make install
```

### Install

To install the extension into your PostgreSQL installation, you can use the `install` command. This will place the extension in the appropriate directory for your PostgreSQL server.

```bash
# Install the extension (requires PostgreSQL development headers)
make install
```

### Test

The project includes a comprehensive test suite. The recommended way to test is using Docker, as it runs in a clean, isolated environment.
```bash
make test-docker
```

### Performance Benchmarks

The extension includes a dedicated performance benchmarking script to help track performance and catch regressions:

```bash
./scripts/benchmark.sh
```

This will:
- Set up a clean testing environment
- Build and install the extension
- Run comprehensive performance tests
- Compare against PostgreSQL's built-in operators
- Display detailed timing results

See [BENCHMARKS.md](docs/BENCHMARKS.md) for detailed performance information and baseline results.

## Examples

### Basic Merge

```sql
SELECT jsonb_merge(
  '{"a": 1, "b": 2}',
  '{"b": 3, "c": 4}'
);
-- Result: {"a": 1, "b": 3, "c": 4}
```

### Recursive Merge

```sql
SELECT jsonb_merge(
  '{"user": {"name": "John", "age": 30}}',
  '{"user": {"age": 31, "email": "john@example.com"}}'
);
-- Result: {"user": {"name": "John", "age": 31, "email": "john@example.com"}}
```

## Development

To clean the build artifacts:
```bash
make clean
```
