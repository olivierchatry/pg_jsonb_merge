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
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    else
        print_error "Neither docker-compose nor docker compose is available."
        exit 1
    fi
    
    # Start container if not running
    if ! docker exec $CONTAINER_NAME pg_isready -U postgres -d postgres >/dev/null 2>&1; then
        print_benchmark "Starting PostgreSQL container..."
        $DOCKER_COMPOSE up -d >/dev/null 2>&1
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
    print_header
    setup_environment
    
    # Benchmark 1: Simple merges
    run_benchmark "Simple object merge" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..10000 LOOP
                result := jsonb_merge('{\"a\": 1, \"b\": 2}', '{\"c\": 3, \"d\": 4}');
            END LOOP;
        END \$\$;
    " 10000
    
    # Benchmark 2: Deep nested merges  
    run_benchmark "Deep nested object merge" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..1000 LOOP
                result := jsonb_merge('{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": 1}}}}}', '{\"a\": {\"b\": {\"c\": {\"d\": {\"f\": 2}}}}}');
            END LOOP;
        END \$\$;
    " 1000
    
    # Benchmark 3: Large objects
    run_benchmark "Large object merge (40 keys each)" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..500 LOOP
                result := jsonb_merge(
                    '{\"k1\": 1, \"k2\": 2, \"k3\": 3, \"k4\": 4, \"k5\": 5, \"k6\": 6, \"k7\": 7, \"k8\": 8, \"k9\": 9, \"k10\": 10, \"k11\": 11, \"k12\": 12, \"k13\": 13, \"k14\": 14, \"k15\": 15, \"k16\": 16, \"k17\": 17, \"k18\": 18, \"k19\": 19, \"k20\": 20}',
                    '{\"k21\": 21, \"k22\": 22, \"k23\": 23, \"k24\": 24, \"k25\": 25, \"k26\": 26, \"k27\": 27, \"k28\": 28, \"k29\": 29, \"k30\": 30, \"k31\": 31, \"k32\": 32, \"k33\": 33, \"k34\": 34, \"k35\": 35, \"k36\": 36, \"k37\": 37, \"k38\": 38, \"k39\": 39, \"k40\": 40}'
                );
            END LOOP;
        END \$\$;
    " 500
    
    # Benchmark 4: Array merging
    run_benchmark "Array merge operations" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..1000 LOOP
                result := jsonb_merge('{\"data\": [1, 2, 3, 4, 5]}', '{\"data\": [6, 7, 8, 9, 10]}', true);
            END LOOP;
        END \$\$;
    " 1000
    
    # Benchmark 5: Mixed complex operations
    run_benchmark "Complex mixed structures" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..100 LOOP
                result := jsonb_merge(
                    '{\"users\": [{\"id\": 1, \"name\": \"Alice\"}, {\"id\": 2, \"name\": \"Bob\"}], \"meta\": {\"count\": 2, \"settings\": {\"theme\": \"dark\", \"lang\": \"en\"}}, \"tags\": [\"user\", \"admin\"]}',
                    '{\"users\": [{\"id\": 3, \"name\": \"Charlie\"}], \"meta\": {\"version\": \"1.0\", \"settings\": {\"debug\": true}}, \"tags\": [\"guest\"], \"extra\": {\"created\": \"2025-01-01\"}}',
                    true
                );
            END LOOP;
        END \$\$;
    " 100
    
    # Benchmark 6: Comparison with built-in operator
    echo -e "${CYAN}📈 Performance Comparison${NC}"
    
    # Our extension
    run_benchmark "jsonb_merge function" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..5000 LOOP
                result := jsonb_merge('{\"a\": 1, \"b\": 2}', '{\"c\": 3, \"d\": 4}');
            END LOOP;
        END \$\$;
    " 5000
    
    # Built-in || operator (for comparison)
    run_benchmark "Built-in || operator" "
        DO \$\$
        DECLARE i integer; result jsonb;
        BEGIN
            FOR i IN 1..5000 LOOP
                result := '{\"a\": 1, \"b\": 2}'::jsonb || '{\"c\": 3, \"d\": 4}'::jsonb;
            END LOOP;
        END \$\$;
    " 5000
    
    echo -e "${GREEN}🎯 Benchmark suite completed!${NC}"
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo -e "   • Run this regularly to catch performance regressions"
    echo -e "   • Compare results before/after code changes"  
    echo -e "   • Built-in || operator only does shallow merge (no recursion)"
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
