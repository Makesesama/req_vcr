# TestApi

A simple test API server for testing ReqVCR.

This application provides a few basic API routes with fake authentication to demonstrate
and test ReqVCR's recording and replay functionality.

## Routes

- `GET /api/users` - Returns a list of users (requires auth)
- `GET /api/users/:id` - Returns a specific user (requires auth)
- `POST /api/users` - Creates a new user (requires auth)

## Authentication

All routes require a `Bearer` token in the `Authorization` header:

```
Authorization: Bearer test-token
```

## Quick Start

The easiest way to record cassettes is using the provided script:

```bash
# From the req_vcr root directory
./scripts/record_cassettes.sh
```

This script will:
1. Install dependencies for the test API
2. Start the test API server
3. Record all cassettes for the example tests
4. Stop the test API server

## Manual Usage

### Running the Server

```bash
# Install dependencies
mix deps.get

# Start the server (default port 4001)
mix run --no-halt

# Start on a different port
PORT=4002 mix run --no-halt
```

### Testing the API

```bash
# With auth (returns users)
curl -H "Authorization: Bearer test-token" http://localhost:4001/api/users

# Without auth (returns 401)
curl http://localhost:4001/api/users

# Get specific user
curl -H "Authorization: Bearer test-token" http://localhost:4001/api/users/1

# Create user
curl -X POST http://localhost:4001/api/users \
  -H "Authorization: Bearer test-token" \
  -H "Content-Type: application/json" \
  -d '{"name":"Charlie","email":"charlie@example.com"}'
```

## Recording Cassettes with ReqVCR

### Using the Script (Recommended)

From the parent `req_vcr` directory:

```bash
./scripts/record_cassettes.sh
```

### Manual Recording

From the parent `req_vcr` directory:

```bash
# 1. Start the test API
cd test_api && mix run --no-halt &

# 2. Record cassettes
cd .. && REQ_VCR=all mix test test/example_api_test.exs

# 3. Replay from cassettes (no network)
mix test test/example_api_test.exs

# 4. Stop the API server
pkill -f "mix run --no-halt"
```
