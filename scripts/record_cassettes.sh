#!/usr/bin/env bash
set -e

# Script to start test API and run tests
# Usage:
#   ./scripts/record_cassettes.sh                                    # Run default tests
#   ./scripts/record_cassettes.sh test/reqord/lifecycle_order_test.exs  # Run specific test file
#   ./scripts/record_cassettes.sh test/reqord/lifecycle_order_test.exs --include integration  # With options

# Parse arguments
TEST_FILES=""
TEST_ARGS=""
RECORD_MODE="all"

# If arguments provided, use them for testing
if [ $# -gt 0 ]; then
    # First argument is the test file
    TEST_FILES="$1"
    shift
    # Remaining arguments are passed to mix test
    TEST_ARGS="$@"
else
    # Default: run the standard test files
    TEST_FILES="default"
fi

echo "Starting test API server..."

# Start the test API in the background
cd test_api
mix deps.get --quiet
MIX_ENV=dev mix run --no-halt &
API_PID=$!
cd ..

# Wait for API to be ready
echo "Waiting for API to start..."
sleep 3

# Check if API is responding
if curl -s -f http://localhost:4001/api/users -H "Authorization: Bearer test-token" > /dev/null 2>&1; then
    echo "API server is ready!"
else
    echo "API server failed to start"
    kill $API_PID 2>/dev/null || true
    exit 1
fi

# Run tests based on arguments
if [ "$TEST_FILES" = "default" ]; then
    # Run ALL tests
    echo "Recording all cassettes..."
    REQORD=$RECORD_MODE mix test --include integration
else
    # Run specified test file with any additional arguments
    echo "Running test: $TEST_FILES $TEST_ARGS"
    REQORD=$RECORD_MODE mix test $TEST_FILES $TEST_ARGS
fi

# Stop the API server
echo "Stopping API server..."
kill $API_PID 2>/dev/null || true
wait $API_PID 2>/dev/null || true

if [ "$TEST_FILES" = "default" ]; then
    echo "Done! Cassettes recorded to test/support/cassettes/"
else
    echo "Done! Test completed."
fi
