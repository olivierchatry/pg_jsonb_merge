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
- **C Implementation**: High-performance merge logic written in C.
- **Debug and Release Builds**: `Makefile` supports both debug and release build modes.
- **Dockerized Testing**: Includes a Docker setup for isolated testing.
- **Cross-Platform**: Builds on macOS and Linux.

## Getting Started

### Prerequisites

- PostgreSQL (with `pg_config`)
- Docker (for containerized testing)
- `make`

### Build

You can build the extension in either release (default) or debug mode.

- **Release Build**:

  ```bash
  make release
  ```

- **Debug Build**:

  ```bash
  make debug
  ```

The compiled library will be located in the `build/` directory (e.g., `build/release/jsonb_merge.dylib`).

### Deploy

To deploy the extension to your PostgreSQL installation, you can use the `deploy` commands.

- **Deploy Release Build**:
  ```bash
  make deploy
  ```

- **Deploy Debug Build**:
  ```bash
  make deploy-debug
  ```

### Test

The project includes a comprehensive test suite.

- **Local Test**:
  This requires a local PostgreSQL server and the `psql` client.
  ```bash
  make test
  ```

- **Dockerized Test**:
  This is the recommended way to test, as it runs in a clean, isolated environment.
  ```bash
  make test-docker
  ```

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
