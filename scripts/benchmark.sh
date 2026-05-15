#!/bin/bash
# benchmark.sh - Comprehensive performance benchmarking for jsonb_merge extension

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="jsonb_merge_test_db"
CSV_FILE="benchmark_results.csv"

print_header() {
    echo -e "${CYAN}🚀 === PostgreSQL JSONB Merge Extension - Performance Benchmarks ===${NC}\n"
}

print_benchmark() {
    echo -e "${BLUE}📊 $1${NC}"
}

print_result() {
    echo -e "${GREEN}   ✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}   ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}   ✗ $1${NC}"
}

# Function to setup the environment
setup_environment() {
    print_benchmark "Setting up benchmark environment..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check for docker-compose or docker compose
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        print_error "Neither docker-compose nor docker compose is available."
        exit 1
    fi
    
    # Start container if not running
    if ! docker exec $CONTAINER_NAME pg_isready -U postgres -d postgres >/dev/null 2>&1; then
        print_benchmark "Starting PostgreSQL container..."
        $DOCKER_COMPOSE_CMD up -d >/dev/null 2>&1
        sleep 3
        
        # Wait for PostgreSQL to be ready
        local attempts=0
        while [ $attempts -lt 30 ]; do
            if docker exec $CONTAINER_NAME pg_isready -U postgres -d postgres >/dev/null 2>&1; then
                break
            fi
            sleep 1
            ((attempts++))
        done
        
        if [ $attempts -eq 30 ]; then
            print_error "PostgreSQL failed to start"
            exit 1
        fi
    fi
    
    # Install build dependencies and build extension
    print_benchmark "Installing and building extension..."
    docker exec $CONTAINER_NAME apk add --no-cache gcc musl-dev make postgresql17-dev >/dev/null 2>&1
    docker cp . $CONTAINER_NAME:/tmp/ >/dev/null 2>&1
    docker exec $CONTAINER_NAME sh -c "cd /tmp && make clean && make install with_llvm=no" >/dev/null 2>&1
    
    # Create extension
    docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "DROP EXTENSION IF EXISTS jsonb_merge; CREATE EXTENSION jsonb_merge;" >/dev/null 2>&1
    
    print_result "Environment ready for benchmarking"
    echo ""
}

# Function to run a benchmark query and extract timing
run_benchmark() {
    local description="$1"
    local sql_query="$2"
    local iterations="$3"
    
    print_benchmark "Running: $description ($iterations iterations)"
    
    # Run the benchmark and capture output
    local output=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "\timing on" -c "$sql_query" -c "\timing off" 2>&1)
    
    # Extract timing information (look for "Time: X.XXX ms")
    local timing=$(echo "$output" | grep -o "Time: [0-9.]*" | grep -o "[0-9.]*" | head -1)
    
    if [ ! -z "$timing" ]; then
        local avg_time=$(echo "scale=6; $timing / $iterations" | bc -l)
        print_result "Total: ${timing} ms, Average: ${avg_time} ms per operation"
        
        # Append to CSV
        echo "\"${description}\",${iterations},${timing},${avg_time}" >> "$CSV_FILE"
        
        # Check for performance warnings (arbitrary thresholds)
        if (( $(echo "$avg_time > 1.0" | bc -l) )); then
            print_warning "Average time > 1ms - consider optimization"
        fi
    else
        echo -e "${RED}   ✗ Could not extract timing information${NC}"
    fi
    
    echo ""
}

# Function to run all benchmarks
run_all_benchmarks() {
    # Initialize CSV
    echo "benchmark,iterations,total_ms,avg_ms" > "$CSV_FILE"
    
    print_header
    setup_environment
    
    # Benchmark 1: Simple merges
    run_benchmark "Simple object merge" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..1000000 LOOP
                result := jsonb_merge('{\"a\": 1, \"b\": 2}', '{\"c\": 3, \"d\": 4}');
            END LOOP;
        END \$\$;
    " 1000000
    
    # Benchmark 2: Deep nested merges  
    run_benchmark "Deep nested object merge" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..100000 LOOP
                result := jsonb_merge('{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": 1}}}}}', '{\"a\": {\"b\": {\"c\": {\"d\": {\"f\": 2}}}}}');
            END LOOP;
        END \$\$;
    " 100000
    
    # Benchmark 3: Large objects
    run_benchmark "Large object merge (40 keys each)" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..50000 LOOP
                result := jsonb_merge(
                    '{\"k1\": 1, \"k2\": 2, \"k3\": 3, \"k4\": 4, \"k5\": 5, \"k6\": 6, \"k7\": 7, \"k8\": 8, \"k9\": 9, \"k10\": 10, \"k11\": 11, \"k12\": 12, \"k13\": 13, \"k14\": 14, \"k15\": 15, \"k16\": 16, \"k17\": 17, \"k18\": 18, \"k19\": 19, \"k20\": 20}',
                    '{\"k21\": 21, \"k22\": 22, \"k23\": 23, \"k24\": 24, \"k25\": 25, \"k26\": 26, \"k27\": 27, \"k28\": 28, \"k29\": 29, \"k30\": 30, \"k31\": 31, \"k32\": 32, \"k33\": 33, \"k34\": 34, \"k35\": 35, \"k36\": 36, \"k37\": 37, \"k38\": 38, \"k39\": 39, \"k40\": 40}'
                );
            END LOOP;
        END \$\$;
    " 50000
    
    # Benchmark 4: Array merging
    run_benchmark "Array merge operations" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..100000 LOOP
                result := jsonb_merge('{\"data\": [1, 2, 3, 4, 5]}', '{\"data\": [6, 7, 8, 9, 10]}', true);
            END LOOP;
        END \$\$;
    " 100000
    
    # Benchmark 5: Mixed complex operations
    run_benchmark "Complex mixed structures" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..10000 LOOP
                result := jsonb_merge(
                    '{\"users\": [{\"id\": 1, \"name\": \"Alice\"}, {\"id\": 2, \"name\": \"Bob\"}], \"meta\": {\"count\": 2, \"settings\": {\"theme\": \"dark\", \"lang\": \"en\"}}, \"tags\": [\"user\", \"admin\"]}',
                    '{\"users\": [{\"id\": 3, \"name\": \"Charlie\"}], \"meta\": {\"version\": \"1.0\", \"settings\": {\"debug\": true}}, \"tags\": [\"guest\"], \"extra\": {\"created\": \"2025-01-01\"}}',
                    true
                );
            END LOOP;
        END \$\$;
    " 10000
    
    # Benchmark 6: Comparison with built-in operator
    echo -e "${CYAN}📈 Performance Comparison (scalar, 500k iterations)${NC}"
    
    run_benchmark "jsonb_merge function" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..500000 LOOP
                result := jsonb_merge('{\"a\": 1, \"b\": 2}', '{\"c\": 3, \"d\": 4}');
            END LOOP;
        END \$\$;
    " 500000
    
    run_benchmark "Built-in || operator" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..500000 LOOP
                result := '{\"a\": 1, \"b\": 2}'::jsonb || '{\"c\": 3, \"d\": 4}'::jsonb;
            END LOOP;
        END \$\$;
    " 500000
    
    # =========================================================================
    # Scaling benchmarks across row counts
    # =========================================================================
    
    # Create PL/pgSQL deep merge function for comparison
    docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
        CREATE OR REPLACE FUNCTION jsonb_deep_merge_sql(a jsonb, b jsonb) RETURNS jsonb AS \$\$
        DECLARE
            result jsonb := a;
            key text;
            val jsonb;
        BEGIN
            FOR key, val IN SELECT * FROM jsonb_each(b) LOOP
                IF result ? key AND jsonb_typeof(result->key) = 'object' AND jsonb_typeof(val) = 'object' THEN
                    result := jsonb_set(result, ARRAY[key], jsonb_deep_merge_sql(result->key, val));
                ELSE
                    result := jsonb_set(result, ARRAY[key], val);
                END IF;
            END LOOP;
            RETURN result;
        END;
        \$\$ LANGUAGE plpgsql IMMUTABLE;
    " >/dev/null 2>&1
    
    ROW_COUNTS="100 1000 10000 100000 1000000"
    
    # ---- Scenario A: Flat object merge (shallow) ----
    echo -e "${CYAN}📈 Scaling: Flat Object Merge (shallow)${NC}"
    
    for N in $ROW_COUNTS; do
        docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            DROP TABLE IF EXISTS bench_scale;
            CREATE TABLE bench_scale (id serial PRIMARY KEY, json1 jsonb, json2 jsonb);
            INSERT INTO bench_scale (json1, json2)
            SELECT
                jsonb_build_object('a', i, 'b', i*2, 'shared', 'from_json1'),
                jsonb_build_object('c', i*3, 'd', i*4, 'shared', 'from_json2')
            FROM generate_series(1, $N) AS i;
            ANALYZE bench_scale;
        " >/dev/null 2>&1
        
        run_benchmark "CTE SQL merge - flat ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                WITH all_json_key_value AS (
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json1) AS t1
                    UNION
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json2) AS t1
                )
                SELECT id, json_object_agg(key, value) AS merged
                FROM all_json_key_value GROUP BY id
            ) sub;
        " $N
        
        run_benchmark "PL/pgSQL merge - flat ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_deep_merge_sql(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "jsonb_merge() - flat ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "|| operator - flat ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, json1 || json2 AS merged FROM bench_scale
            ) sub;
        " $N
    done
    
    # ---- Scenario B: 3-level nested object merge ----
    echo -e "${CYAN}📈 Scaling: 3-Level Nested Object Merge${NC}"
    
    for N in $ROW_COUNTS; do
        docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            DROP TABLE IF EXISTS bench_scale;
            CREATE TABLE bench_scale (id serial PRIMARY KEY, json1 jsonb, json2 jsonb);
            INSERT INTO bench_scale (json1, json2)
            SELECT
                jsonb_build_object(
                    'config', jsonb_build_object(
                        'database', jsonb_build_object('host', 'db-' || i, 'port', 5432 + (i % 100), 'pool', jsonb_build_object('min', 1 + (i % 5), 'max', 10 + (i % 20))),
                        'cache', jsonb_build_object('ttl', 3600 + (i % 1000), 'backend', 'redis'),
                        'logging', jsonb_build_object('level', 'info', 'format', 'json')
                    ),
                    'users', jsonb_build_object('count', i, 'active', (i % 2 = 0)),
                    'version', '1.' || (i % 10)
                ),
                jsonb_build_object(
                    'config', jsonb_build_object(
                        'database', jsonb_build_object('port', 5433 + (i % 50), 'ssl', (i % 3 = 0), 'pool', jsonb_build_object('max', 20 + (i % 30), 'idle_timeout', 30 + (i % 60))),
                        'cache', jsonb_build_object('ttl', 7200 + (i % 2000), 'compression', (i % 2 = 1)),
                        'monitoring', jsonb_build_object('enabled', (i % 4 = 0), 'interval', 30 + (i % 120))
                    ),
                    'users', jsonb_build_object('count', i*2, 'roles', '[\"admin\",\"user\"]'::jsonb),
                    'deployed', (i % 5 = 0)
                )
            FROM generate_series(1, $N) AS i;
            ANALYZE bench_scale;
        " >/dev/null 2>&1
        
        run_benchmark "CTE SQL merge - 3-level ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                WITH all_json_key_value AS (
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json1) AS t1
                    UNION
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json2) AS t1
                )
                SELECT id, json_object_agg(key, value) AS merged
                FROM all_json_key_value GROUP BY id
            ) sub;
        " $N
        
        run_benchmark "PL/pgSQL deep merge - 3-level ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_deep_merge_sql(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "jsonb_merge() - 3-level ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
    done
    
    # ---- Scenario C: 4+ level real-world config merge ----
    echo -e "${CYAN}📈 Scaling: 4+ Level Real-World Config Merge${NC}"
    
    for N in $ROW_COUNTS; do
        docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            DROP TABLE IF EXISTS bench_scale;
            CREATE TABLE bench_scale (id serial PRIMARY KEY, json1 jsonb, json2 jsonb);
            INSERT INTO bench_scale (json1, json2)
            SELECT
                jsonb_build_object(
                    'app', jsonb_build_object('name', 'myapp-' || i, 'env', 'production', 'features', jsonb_build_object('auth', (i % 2 = 0), 'cache', true, 'notifications', jsonb_build_object('email', (i % 3 = 0), 'sms', false, 'push', jsonb_build_object('enabled', true, 'provider', 'firebase', 'priority', i % 10)))),
                    'db', jsonb_build_object('primary', jsonb_build_object('host', 'db' || (i % 10) || '.example.com', 'port', 5432 + (i % 100), 'credentials', jsonb_build_object('user', 'app', 'pool_size', 5 + (i % 20))), 'replica', jsonb_build_object('host', 'replica' || (i % 5) || '.example.com', 'port', 5432)),
                    'api', jsonb_build_object('rate_limit', jsonb_build_object('window', 30 + (i % 120), 'max_requests', 500 + (i % 1000)), 'cors', jsonb_build_object('origins', jsonb_build_array('https://app' || (i % 100) || '.example.com'), 'methods', jsonb_build_array('GET', 'POST')))
                ),
                jsonb_build_object(
                    'app', jsonb_build_object('env', 'staging', 'debug', (i % 2 = 1), 'features', jsonb_build_object('cache', (i % 4 = 0), 'notifications', jsonb_build_object('sms', (i % 3 = 1), 'push', jsonb_build_object('provider', 'apns', 'badge', i % 99)))),
                    'db', jsonb_build_object('primary', jsonb_build_object('host', 'staging-db' || (i % 5) || '.example.com', 'credentials', jsonb_build_object('pool_size', 3 + (i % 10)))),
                    'api', jsonb_build_object('rate_limit', jsonb_build_object('max_requests', 50 + (i % 200)), 'version', 'v' || (1 + (i % 5)))
                )
            FROM generate_series(1, $N) AS i;
            ANALYZE bench_scale;
        " >/dev/null 2>&1
        
        run_benchmark "CTE SQL merge - config ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                WITH all_json_key_value AS (
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json1) AS t1
                    UNION
                    SELECT id, t1.key, t1.value FROM bench_scale, jsonb_each(json2) AS t1
                )
                SELECT id, json_object_agg(key, value) AS merged
                FROM all_json_key_value GROUP BY id
            ) sub;
        " $N
        
        run_benchmark "PL/pgSQL deep merge - config ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_deep_merge_sql(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "jsonb_merge() - config ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
    done
    
    # ---- Scenario D: Array merge ----
    echo -e "${CYAN}📈 Scaling: Array Merge${NC}"
    
    for N in $ROW_COUNTS; do
        docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            DROP TABLE IF EXISTS bench_scale;
            CREATE TABLE bench_scale (id serial PRIMARY KEY, json1 jsonb, json2 jsonb);
            INSERT INTO bench_scale (json1, json2)
            SELECT
                jsonb_build_object(
                    'tags', jsonb_build_array('alpha', 'beta', 'gamma'),
                    'scores', jsonb_build_array(i, i*2, i*3),
                    'meta', jsonb_build_object('items', jsonb_build_array(1, 2, 3))
                ),
                jsonb_build_object(
                    'tags', jsonb_build_array('delta', 'epsilon'),
                    'scores', jsonb_build_array(i*4, i*5),
                    'meta', jsonb_build_object('items', jsonb_build_array(4, 5, 6))
                )
            FROM generate_series(1, $N) AS i;
            ANALYZE bench_scale;
        " >/dev/null 2>&1
        
        run_benchmark "jsonb_merge(merge_arrays=true) - arrays ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2, true) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "jsonb_merge(merge_arrays=false) - arrays ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "|| operator - arrays ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, json1 || json2 AS merged FROM bench_scale
            ) sub;
        " $N
    done
    
    # ---- Scenario E: Heavy objects with many keys and randomized data ----
    echo -e "${CYAN}📈 Scaling: Heavy Objects (20+ keys, randomized, 3-level deep)${NC}"
    
    for N in $ROW_COUNTS; do
        docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            DROP TABLE IF EXISTS bench_scale;
            CREATE TABLE bench_scale (id serial PRIMARY KEY, json1 jsonb, json2 jsonb);
            INSERT INTO bench_scale (json1, json2)
            SELECT
                jsonb_build_object(
                    'user', jsonb_build_object(
                        'id', md5(random()::text),
                        'name', md5(random()::text) || ' ' || md5(random()::text),
                        'email', md5(random()::text) || '@example.com',
                        'bio', repeat(md5(random()::text), 4),
                        'preferences', jsonb_build_object(
                            'theme', md5(random()::text),
                            'language', md5(random()::text),
                            'timezone', md5(random()::text),
                            'notifications', jsonb_build_object('email', random() > 0.5, 'sms', random() > 0.5, 'push', random() > 0.5, 'frequency', md5(random()::text))
                        ),
                        'address', jsonb_build_object('street', md5(random()::text), 'city', md5(random()::text), 'zip', md5(random()::text), 'country', md5(random()::text))
                    ),
                    'metrics', jsonb_build_object(
                        'visits', (random() * 10000)::int,
                        'clicks', (random() * 5000)::int,
                        'conversions', (random() * 100)::int,
                        'revenue', round((random() * 10000)::numeric, 2),
                        'sessions', jsonb_build_object('avg_duration', round((random() * 300)::numeric, 1), 'bounce_rate', round((random())::numeric, 3), 'pages_per_session', round((random() * 10)::numeric, 1))
                    ),
                    'permissions', jsonb_build_object(
                        'roles', jsonb_build_array(md5(random()::text), md5(random()::text), md5(random()::text)),
                        'scopes', jsonb_build_object('read', random() > 0.5, 'write', random() > 0.5, 'admin', random() > 0.5, 'audit', random() > 0.5),
                        'last_login', md5(random()::text),
                        'mfa_enabled', random() > 0.5
                    ),
                    'metadata', jsonb_build_object(
                        'created_at', md5(random()::text),
                        'updated_at', md5(random()::text),
                        'version', (random() * 100)::int,
                        'tags', jsonb_build_array(md5(random()::text), md5(random()::text), md5(random()::text), md5(random()::text)),
                        'extra', jsonb_build_object('field1', md5(random()::text), 'field2', md5(random()::text), 'field3', md5(random()::text))
                    )
                ),
                jsonb_build_object(
                    'user', jsonb_build_object(
                        'name', md5(random()::text) || ' ' || md5(random()::text),
                        'avatar', md5(random()::text) || '.png',
                        'bio', repeat(md5(random()::text), 3),
                        'preferences', jsonb_build_object(
                            'theme', md5(random()::text),
                            'sidebar', random() > 0.5,
                            'notifications', jsonb_build_object('push', random() > 0.5, 'digest', random() > 0.5, 'frequency', md5(random()::text))
                        ),
                        'address', jsonb_build_object('city', md5(random()::text), 'state', md5(random()::text), 'country', md5(random()::text))
                    ),
                    'metrics', jsonb_build_object(
                        'visits', (random() * 10000)::int,
                        'conversions', (random() * 200)::int,
                        'revenue', round((random() * 20000)::numeric, 2),
                        'sessions', jsonb_build_object('avg_duration', round((random() * 600)::numeric, 1), 'pages_per_session', round((random() * 15)::numeric, 1), 'new_metric', round((random() * 100)::numeric, 2))
                    ),
                    'permissions', jsonb_build_object(
                        'roles', jsonb_build_array(md5(random()::text), md5(random()::text)),
                        'scopes', jsonb_build_object('write', random() > 0.5, 'admin', random() > 0.5, 'deploy', random() > 0.5),
                        'mfa_enabled', random() > 0.5,
                        'ip_whitelist', jsonb_build_array(md5(random()::text), md5(random()::text))
                    ),
                    'metadata', jsonb_build_object(
                        'updated_at', md5(random()::text),
                        'version', (random() * 100)::int,
                        'tags', jsonb_build_array(md5(random()::text), md5(random()::text)),
                        'extra', jsonb_build_object('field2', md5(random()::text), 'field4', md5(random()::text), 'field5', md5(random()::text))
                    )
                )
            FROM generate_series(1, $N) AS i;
            ANALYZE bench_scale;
        " >/dev/null 2>&1
        
        run_benchmark "PL/pgSQL deep merge - heavy ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_deep_merge_sql(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
        
        run_benchmark "jsonb_merge() - heavy ${N} rows" "
            SELECT sum(pg_column_size(merged)) FROM (
                SELECT id, jsonb_merge(json1, json2) AS merged FROM bench_scale
            ) sub;
        " $N
    done
    
    # Cleanup
    docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
        DROP TABLE IF EXISTS bench_scale;
        DROP FUNCTION IF EXISTS jsonb_deep_merge_sql(jsonb, jsonb);
    " >/dev/null 2>&1
    
    echo -e "${GREEN}🎯 Benchmark suite completed!${NC}"
    echo -e "${GREEN}   CSV results written to: ${CSV_FILE}${NC}"
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo -e "   • Run this regularly to catch performance regressions"
    echo -e "   • Compare results before/after code changes"  
    echo -e "   • Built-in || operator only does shallow merge (no recursion)"
    echo -e "   • Recursive SQL merge uses CTE + jsonb_each + UNION + json_object_agg"
    echo -e "   • Our extension provides deep recursive merging"
    echo -e "   • Use './test/docker-test.sh' for correctness tests"
}

# Check if bc (calculator) is available
if ! command -v bc >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Warning: 'bc' calculator not found. Install with: brew install bc${NC}"
    echo -e "${YELLOW}  Average calculations will be skipped.${NC}\n"
fi

# Run the benchmarks
run_all_benchmarks
