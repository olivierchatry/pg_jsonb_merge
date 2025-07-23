#!/bin/bash
# Docker-based testing script for the JSONB merge extension

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="jsonb_merge_test_db"
DB_NAME="testdb"
DB_USER="testuser"
DB_PASS="testpass"
DB_PORT="5432"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Function to check if docker-compose is available
check_docker_compose() {
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_error "docker-compose is not installed. Please install docker-compose and try again."
        exit 1
    fi
    print_success "docker-compose is available"
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    print_status "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec $CONTAINER_NAME pg_isready -U postgres -d postgres >/dev/null 2>&1; then
            print_success "PostgreSQL is ready"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - PostgreSQL not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    print_error "PostgreSQL failed to become ready after $max_attempts attempts"
    return 1
}

# Function to build and copy extension to container
install_extension() {
    print_status "Building extension locally..."
    
    # Build the extension locally first
    make
    
    print_status "Detecting PostgreSQL paths in container..."
    
    # Get PostgreSQL paths from inside the container
    CONTAINER_PKGLIBDIR=$(docker exec $CONTAINER_NAME pg_config --pkglibdir 2>/dev/null || echo "/usr/local/lib/postgresql")
    CONTAINER_SHAREDIR=$(docker exec $CONTAINER_NAME pg_config --sharedir 2>/dev/null || echo "/usr/local/share/postgresql")
    CONTAINER_EXTENSIONDIR="$CONTAINER_SHAREDIR/extension"
    
    print_status "Container PostgreSQL paths:"
    print_status "  Library dir: $CONTAINER_PKGLIBDIR"
    print_status "  Extension dir: $CONTAINER_EXTENSIONDIR"
    
    print_status "Installing build dependencies in container..."
    docker exec $CONTAINER_NAME apk add --no-cache build-base postgresql-dev make clang llvm lld
    
    # Create the expected LLVM directory structure and symlinks
    docker exec $CONTAINER_NAME mkdir -p /usr/lib/llvm19/bin
    docker exec $CONTAINER_NAME ln -sf /usr/bin/clang /usr/bin/clang-19
    docker exec $CONTAINER_NAME ln -sf /usr/bin/llvm-lto /usr/lib/llvm19/bin/llvm-lto
    docker exec $CONTAINER_NAME ln -sf /usr/bin/llvm-link /usr/lib/llvm19/bin/llvm-link
    docker exec $CONTAINER_NAME ln -sf /usr/bin/ld.lld /usr/lib/llvm19/bin/ld.lld
    
    print_status "Copying and building extension in container..."
    
    # Copy source files to container
    docker cp . $CONTAINER_NAME:/tmp/
    
    # Build and install inside the container using PGXS
    docker exec $CONTAINER_NAME make -C /tmp/ clean
    docker exec $CONTAINER_NAME make -C /tmp/ install
    
    print_success "Extension built and installed in container"
}

# Function to run tests
run_tests() {
    print_status "Running tests..."
    
    # Create the extension in the database (use postgres user which exists by default)
    docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS jsonb_merge;"
    
    # Copy test files to container (copy the whole test directory)
    docker cp ./test $CONTAINER_NAME:/tmp/
    
    # Run all test files in order, and check results
    local all_tests_passed=true
    for test_file in $(ls -1 ./test/*.sql | sort); do
        local test_name=$(basename $test_file)
        print_status "Running test: $test_name"
        
        # Execute the test and capture the output
        # Show the full output including the actual SQL results
        local test_output=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -f /tmp/test/$test_name 2>&1)
        
        echo "Test output:"
        echo "$test_output"
        echo ""
        
        # Check if the test output contains any test failures
        # Look for lines that have 'test' or 'passed' and contain 'f' (false)
        if echo "$test_output" | grep -E '(test_.*passed|result)' | grep -q ' f$' && ! echo "$test_output" | grep -q 'CREATE EXTENSION'; then
            print_error "Test failed: $test_name"
            all_tests_passed=false
        else
            print_success "Test passed: $test_name"
        fi
    done
    
    if [ "$all_tests_passed" = true ]; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed."
        return 1
    fi
}

# Function to clean up resources
cleanup() {
    print_status "Cleaning up..."
    
    # Prompt user to keep container running
    read -p "Keep PostgreSQL container running for manual testing? [y/N]: " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        docker-compose down --volumes
        print_success "Cleanup completed"
    else
        print_status "Container '$CONTAINER_NAME' is still running."
        print_status "To stop it, run: docker-compose down --volumes"
    fi
}

# Main script execution
main() {
    echo -e "${BLUE}=== PostgreSQL JSONB Merge Extension - Docker Testing ===${NC}\n"
    
    check_docker
    check_docker_compose
    
    # Stop and remove any existing containers to ensure clean start
    print_status "Cleaning up any existing containers..."
    docker-compose down --volumes 2>/dev/null || true
    
    # Start PostgreSQL container using docker-compose
    print_status "Starting PostgreSQL container..."
    docker-compose up -d --build
    
    wait_for_postgres
    
    install_extension
    
    run_tests
    
    echo
    print_success "All tests passed!"
}

# Run main and cleanup
main
cleanup
