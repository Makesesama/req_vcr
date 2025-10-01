#!/usr/bin/env bash
set -e

# Script to start test API and record cassettes
# Usage: ./scripts/record_cassettes.sh

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

# Record cassettes
echo "Recording cassettes..."
REQ_VCR=all mix test test/example_api_test.exs

# Stop the API server
echo "Stopping API server..."
kill $API_PID 2>/dev/null || true
wait $API_PID 2>/dev/null || true

echo "Done! Cassettes recorded to test/support/cassettes/ExampleAPI/"
