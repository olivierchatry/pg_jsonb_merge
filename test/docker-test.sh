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
        print_error "🐋 Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "🐋 Docker is running"
}

# Function to check if docker-compose is available
check_docker_compose() {
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_error "🐙 docker-compose is not installed. Please install docker-compose and try again."
        exit 1
    fi
    print_success "🐙 docker-compose is available"
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    print_status "⏳ Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec $CONTAINER_NAME pg_isready -U postgres -d postgres >/dev/null 2>&1; then
            print_success "🐘 PostgreSQL is ready"
            return 0
        fi
        
        print_status "⏳ Attempt $attempt/$max_attempts - PostgreSQL not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    print_error "💥 PostgreSQL failed to become ready after $max_attempts attempts"
    return 1
}

# Function to build and copy extension to container
install_extension() {
    print_status "🔨 Building extension locally..."
    
    # Build the extension locally first
    make >/dev/null 2>&1
    
    print_status "🔍 Detecting PostgreSQL paths in container..."
    
    # Get PostgreSQL paths from inside the container
    CONTAINER_PKGLIBDIR=$(docker exec $CONTAINER_NAME pg_config --pkglibdir 2>/dev/null || echo "/usr/local/lib/postgresql")
    CONTAINER_SHAREDIR=$(docker exec $CONTAINER_NAME pg_config --sharedir 2>/dev/null || echo "/usr/local/share/postgresql")
    CONTAINER_EXTENSIONDIR="$CONTAINER_SHAREDIR/extension"
    
    print_status "📁 Container PostgreSQL paths:"
    print_status "  📚 Library dir: $CONTAINER_PKGLIBDIR"
    print_status "  📦 Extension dir: $CONTAINER_EXTENSIONDIR"
    
    print_status "📥 Installing build dependencies in container..."
    # Install only the essential packages needed for building PostgreSQL extensions
    docker exec $CONTAINER_NAME apk add --no-cache \
        gcc \
        musl-dev \
        make \
        postgresql17-dev >/dev/null 2>&1
    
    print_status "🔧 Copying and building extension in container..."
    
    # Copy source files to container
    docker cp . $CONTAINER_NAME:/tmp/ >/dev/null 2>&1
    
    # Build and install inside the container using PGXS
    docker exec $CONTAINER_NAME make -C /tmp/ clean >/dev/null 2>&1
    docker exec $CONTAINER_NAME sh -c "cd /tmp && make install with_llvm=no" >/dev/null 2>&1
    
    print_success "✅ Extension built and installed in container"
}

# Function to run tests
run_tests() {
    print_status "🧪 Running test suite..."
    
    # Create the extension in the database (use postgres user which exists by default)
    docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS jsonb_merge;" >/dev/null 2>&1
    
    # Copy test files to container (copy the whole test directory)
    docker cp ./test $CONTAINER_NAME:/tmp/ >/dev/null 2>&1
    
    # Run all test files in order, and check results
    local all_tests_passed=true
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for test_file in $(ls -1 ./test/*.sql | sort); do
        local test_name=$(basename $test_file .sql)
        total_tests=$((total_tests + 1))
        
        # Execute the test and capture the output
        local test_output=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -f /tmp/test/$(basename $test_file) 2>&1)
        
        # Extract test description from echo output
        local test_description=$(echo "$test_output" | grep -E "^Test [0-9]+:" | head -1)
        if [ -z "$test_description" ]; then
            test_description="Test $(basename $test_file)"
        fi
        
        # Check if the test output contains any test failures
        local has_failure=false
        # Look for test_passed with value 'f' (false)
        if echo "$test_output" | grep -E '(test_.*passed)' | grep -A1 ' test_passed ' | grep -q ' f$'; then
            has_failure=true
        fi
        
        # Also check for lines ending with ' f' (simpler check)
        if echo "$test_output" | grep -q ' f$'; then
            has_failure=true
        fi
        
        # Check for SQL errors
        if echo "$test_output" | grep -q "ERROR:"; then
            has_failure=true
        fi
        
        if [ "$has_failure" = true ]; then
            echo -e "  ❌ ${RED}$test_description${NC}"
            echo -e "     ${YELLOW}📋 Test Details:${NC}"
            
            # Extract the actual result (the first result after "result" header)
            local actual_result=$(echo "$test_output" | grep -A3 "result" | grep -v "result" | grep -v "^--" | grep -v "^(" | head -1 | xargs)
            
            # Try to extract the inputs from the test file
            local test_file_content=$(cat "./test/$(basename $test_file)")
            
            # Extract inputs - handle multi-line jsonb_merge calls
            local jsonb_call=$(echo "$test_file_content" | grep -A5 "jsonb_merge" | head -6 | tr '\n' ' ' | sed 's/SELECT jsonb_merge(//' | sed 's/) AS.*//' | sed 's/) =.*//')
            local input1=$(echo "$jsonb_call" | cut -d',' -f1 | xargs | sed "s/^'//; s/'$//")
            local input2=$(echo "$jsonb_call" | cut -d',' -f2 | xargs | sed "s/^'//; s/'$//")
            
            # Clean up inputs - remove leading/trailing whitespace and quotes
            input1=$(echo "$input1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed "s/^'//; s/'$//" | sed 's/^"//; s/"$//')
            input2=$(echo "$input2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed "s/^'//; s/'$//" | sed 's/^"//; s/"$//')
            
            # Try to extract the expected value from the test file
            local expected_result=$(echo "$test_file_content" | grep -o "= '[^']*'" | head -1 | sed "s/= '//; s/'$//")
            
            # If we couldn't extract from single quotes, try double quotes
            if [ -z "$expected_result" ]; then
                expected_result=$(echo "$test_file_content" | grep -o '= "[^"]*"' | head -1 | sed 's/= "//; s/"$//')
            fi
            
            # If still empty, try to extract JSON pattern
            if [ -z "$expected_result" ]; then
                expected_result=$(echo "$test_file_content" | grep -o '= {[^}]*}' | head -1 | sed 's/= //')
            fi
            
            # Show inputs, expected, and actual in a clear flow
            if [ ! -z "$input1" ] && [ ! -z "$input2" ]; then
                echo -e "     ${BLUE}📥 Input 1:${NC}  $input1"
                echo -e "     ${BLUE}📥 Input 2:${NC}  $input2"
            fi
            
            if [ ! -z "$expected_result" ]; then
                echo -e "     ${GREEN}✅ Expected:${NC} $expected_result"
            else
                echo -e "     ${GREEN}✅ Expected:${NC} (check test comparison logic)"
            fi
            
            if [ ! -z "$actual_result" ]; then
                echo -e "     ${RED}🔍 Actual:${NC}   $actual_result"
            fi
            
            # Show error messages if any
            local error_msg=$(echo "$test_output" | grep "ERROR:" | head -1)
            if [ ! -z "$error_msg" ]; then
                echo -e "     ${RED}💥 Error:${NC}    $error_msg"
            fi
            
            echo ""
            all_tests_passed=false
            failed_tests=$((failed_tests + 1))
        else
            echo -e "  ✅ ${GREEN}$test_description${NC}"
            passed_tests=$((passed_tests + 1))
        fi
    done
    
    echo ""
    echo -e "${BLUE}📊 Test Summary:${NC}"
    echo -e "   Total: $total_tests"
    echo -e "   ${GREEN}✅ Passed: $passed_tests${NC}"
    
    if [ $failed_tests -gt 0 ]; then
        echo -e "   ${RED}❌ Failed: $failed_tests${NC}"
        print_error "❌ Some tests failed."
        return 1
    else
        echo -e "   ${RED}❌ Failed: 0${NC}"
        print_success "🎉 All tests passed!"
        return 0
    fi
}

# Function to clean up resources
cleanup() {
    print_status "🧹 Cleaning up..."
    
    # Prompt user to keep container running
    read -p "🤔 Keep PostgreSQL container running for manual testing? [y/N]: " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        docker-compose down --volumes >/dev/null 2>&1
        print_success "✨ Cleanup completed"
    else
        print_status "🏃 Container '$CONTAINER_NAME' is still running."
        print_status "🛑 To stop it, run: docker-compose down --volumes"
    fi
}

# Main script execution
main() {
    echo -e "${BLUE}🚀 === PostgreSQL JSONB Merge Extension - Docker Testing ===${NC}\n"
    
    check_docker
    check_docker_compose
    
    # Stop and remove any existing containers to ensure clean start
    print_status "🧹 Cleaning up any existing containers..."
    docker-compose down --volumes 2>/dev/null || true
    
    # Start PostgreSQL container using docker-compose
    print_status "🐘 Starting PostgreSQL container..."
    docker-compose up -d --build >/dev/null 2>&1
    
    wait_for_postgres
    
    install_extension
    
    run_tests
}

# Run main and cleanup
main
cleanup
