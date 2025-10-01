# ReqVCR

VCR-style HTTP recording and replay for Elixir's [Req](https://hexdocs.pm/req) library, with zero application code changes required.

ReqVCR integrates seamlessly with `Req.Test` to automatically record HTTP interactions to cassette files and replay them in your tests. Perfect for testing applications that interact with external APIs.

## Features

- **Zero app code changes** - Works entirely through `Req.Test` integration
- **Three modes** - Replay (default), Record, and Auto (record on miss)
- **Smart matching** - Requests matched by method, normalized URL, and body hash
- **Automatic redaction** - Auth headers and query params are automatically redacted
- **Concurrent tests** - Full support for async ExUnit tests with private ownership
- **Spawned processes** - Easy allowance API for Tasks and spawned processes

## Installation

Add `req_vcr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req, "~> 0.5"},
    {:req_vcr, "~> 0.1.0"}
  ]
end
```

## Setup

### 1. Configure Req to use Req.Test in your test environment

In `config/test.exs`:

```elixir
# If you're building a library that uses Req
config :my_app,
  req_options: [plug: {Req.Test, MyApp.ReqStub}]

# Then in your application code, use these options:
Req.new(Application.get_env(:my_app, :req_options, []))
```

Or if you're using Req directly in tests:

```elixir
# In your test setup
Req.new(plug: {Req.Test, MyApp.ReqStub})
```

### 2. Use ReqVCR.Case in your tests

```elixir
defmodule MyApp.APITest do
  use ReqVCR.Case

  # Your Req.Test stub name (must match the one in config)
  defp default_stub_name, do: MyApp.ReqStub

  test "fetches user data" do
    # This request will be recorded/replayed automatically
    {:ok, response} = Req.get(client(), url: "/users/123")
    assert response.status == 200
    assert response.body["name"] == "John Doe"
  end

  defp client do
    Req.new(Application.get_env(:my_app, :req_options, []))
  end
end
```

## Usage

### Record Modes

ReqVCR supports Ruby VCR-style record modes. Control via environment variable, config, or test tags.

#### Available Modes

- **`:once`** (default) - Strict replay. Use existing cassette, raise on new requests
- **`:new_episodes`** - Append mode. Replay existing, record new requests  
- **`:all`** - Always re-record. Ignores cassette, hits live network
- **`:none`** - Never record. Must have complete cassette

#### Environment Variable

```bash
# Once mode (default) - strict replay
REQ_VCR=once mix test

# New episodes mode - append new recordings
REQ_VCR=new_episodes mix test

# All mode - always re-record everything
REQ_VCR=all API_TOKEN=xxx mix test

# None mode - never record, never hit network
REQ_VCR=none mix test
```

Legacy mode names still work:
```bash
REQ_VCR=replay mix test    # → :once
REQ_VCR=auto mix test      # → :new_episodes  
REQ_VCR=record mix test    # → :all
```

#### Application Config

```elixir
# config/test.exs
config :req_vcr, default_mode: :once
```

#### Per-Test Override

```elixir
@tag vcr_mode: :new_episodes
test "allows new recordings" do
  # This test will record new requests
end
```

### Cassette Naming

Cassettes are automatically named based on your test module and test name:

```elixir
defmodule MyApp.UserAPITest do
  use ReqVCR.Case

  # Creates cassette: test/support/cassettes/UserAPI/fetches_user_list.jsonl
  test "fetches user list" do
    # ...
  end

  # Override with custom name
  @tag vcr: "custom/my_cassette"
  test "with custom cassette" do
    # Creates cassette: test/support/cassettes/custom/my_cassette.jsonl
  end
end
```

### Custom Stub Names

Override the stub name per test if needed:

```elixir
@tag req_stub_name: MyApp.OtherStub
test "with different stub" do
  # Uses MyApp.OtherStub instead of default
end
```

### Working with Spawned Processes

If your test spawns processes that make HTTP requests, allow them access to the stub:

```elixir
test "with spawned task" do
  task = Task.async(fn ->
    Req.get(client(), url: "/data")
  end)

  # Allow the task's process to use the stub
  ReqVCR.allow(MyApp.ReqStub, self(), task.pid)

  {:ok, response} = Task.await(task)
  assert response.status == 200
end
```

## How It Works

### Request Matching

ReqVCR matches requests using a deterministic key:

```
METHOD NORMALIZED_URL BODY_HASH
```

- **Method**: HTTP method (GET, POST, etc.)
- **Normalized URL**: 
  - Query parameters sorted lexicographically
  - Auth params (`token`, `apikey`) removed
- **Body Hash**: 
  - SHA-256 hash for POST/PUT/PATCH
  - `-` for other methods

This means:
- Query parameter order doesn't affect matching
- Auth parameters don't affect matching
- Different request bodies produce different keys

### Cassette Format

Cassettes are stored as JSONL (JSON Lines) files in `test/support/cassettes/`:

```json
{"key":"GET https://api.example.com/users -","req":{...},"resp":{...}}
{"key":"POST https://api.example.com/users abc123...","req":{...},"resp":{...}}
```

Each line is a JSON object containing:
- `key` - The match key
- `req` - Request details (method, URL, headers)
- `resp` - Response (status, headers, base64-encoded body)

### Redaction

ReqVCR automatically redacts sensitive data:

**Headers** (set to `<REDACTED>`):
- `authorization`

**Query parameters** (set to `<REDACTED>`):
- `token`
- `apikey`
- `api_key`

**Volatile response headers** (removed):
- `date`, `server`, `set-cookie`
- `request-id`, `x-request-id`, `x-amzn-trace-id`

## Example Workflow

```bash
# 1. Write your test using ReqVCR.Case
# 2. Record cassettes (hits live API)
REQ_VCR=record API_TOKEN=xxx mix test --include vcr

# 3. Commit cassettes to git
git add test/support/cassettes/
git commit -m "Add API cassettes"

# 4. Run tests in replay mode (no network calls)
mix test

# 5. Update cassettes when API changes
REQ_VCR=record API_TOKEN=xxx mix test --include vcr
```

## Integration with Req.Test

ReqVCR works alongside your existing `Req.Test` stubs and expectations:

```elixir
test "with mixed stubs" do
  # Add a high-priority stub for specific URL
  Req.Test.stub(MyApp.ReqStub, fn
    %{request_path: "/special"} = conn ->
      Req.Test.json(conn, %{special: true})
  end)

  # This request hits your stub
  {:ok, resp1} = Req.get(client(), url: "/special")
  assert resp1.body["special"] == true

  # This request falls through to VCR
  {:ok, resp2} = Req.get(client(), url: "/other")
  # Replayed from cassette or recorded
end
```

## Advanced Configuration

### Custom Default Stub Name

```elixir
defmodule MyApp.APITest do
  use ReqVCR.Case

  # Override for all tests in this module
  defp default_stub_name, do: MyApp.CustomStub
end
```

### Programmatic Installation

For advanced use cases, you can install VCR manually:

```elixir
setup do
  ReqVCR.install!(
    name: MyApp.ReqStub,
    cassette: "my_test",
    mode: :replay
  )

  :ok
end
```

## CLI Commands

ReqVCR provides several Mix tasks to help manage your cassettes:

### `mix req_vcr.show`

Display cassette contents in a readable format:

```bash
# Show all entries in a cassette
mix req_vcr.show MyTest/my_test.jsonl

# Filter by URL pattern
mix req_vcr.show MyTest/my_test.jsonl --grep "/users"

# Filter by HTTP method
mix req_vcr.show MyTest/my_test.jsonl --method POST

# Show raw JSON
mix req_vcr.show MyTest/my_test.jsonl --raw

# Decode and pretty-print JSON response bodies
mix req_vcr.show MyTest/my_test.jsonl --decode-body
```

### `mix req_vcr.audit`

Audit cassettes for potential issues:

```bash
# Run all audits
mix req_vcr.audit

# Check for potential secrets only
mix req_vcr.audit --secrets-only

# Find stale cassettes (older than 90 days)
mix req_vcr.audit --stale-days 90
```

The audit task reports:
- **Secrets**: Potential sensitive data that should be redacted (tokens, API keys, etc.)
- **Stale cassettes**: Files older than specified days
- **Unused cassettes**: Entries not hit during test runs (requires coverage data)

### `mix req_vcr.prune`

Clean up cassette files:

```bash
# Preview what would be removed (dry run)
mix req_vcr.prune --dry-run

# Remove empty cassettes and duplicates
mix req_vcr.prune

# Remove cassettes older than 180 days
mix req_vcr.prune --stale-days 180

# Remove only duplicate entries
mix req_vcr.prune --duplicates-only

# Remove only empty files
mix req_vcr.prune --empty-only

# Skip confirmation
mix req_vcr.prune --force
```

### `mix req_vcr.rename`

Rename or move cassette files:

```bash
# Rename a single cassette
mix req_vcr.rename old_name.jsonl new_name.jsonl

# Move all cassettes from one module to another
mix req_vcr.rename --from "OldModule/" --to "NewModule/"

# Preview changes
mix req_vcr.rename --from "OldModule/" --to "NewModule/" --dry-run

# Migrate cassettes to latest schema (for future schema changes)
mix req_vcr.rename --migrate
```

## Example API for Testing

This repository includes a test API server (`test_api/`) for demonstrating ReqVCR's functionality. It's a simple REST API with authentication that's used in the example tests.

### Quick Start

Use the provided script to automatically record example cassettes:

```bash
./scripts/record_cassettes.sh
```

This will:
1. Start the test API server
2. Record all example test cassettes
3. Stop the server

### Running Example Tests

```bash
# Run in replay mode (uses pre-recorded cassettes, no network)
mix test test/example_api_test.exs

# Re-record cassettes
REQ_VCR=all mix test test/example_api_test.exs
```

See `test_api/README.md` for more details on the test API.

## Troubleshooting

### "No cassette entry found" error

This means you're in `:once` mode but the cassette doesn't have a matching entry.

**Solution**: Record the cassette first:

```bash
REQ_VCR=all mix test
```

Or use new_episodes mode to record on misses:

```bash
REQ_VCR=new_episodes mix test
```

### Tests fail with "No Req.Test stub found"

Make sure you've configured `Req.Test` in your test config and are using the correct stub name.

### Spawned processes can't make requests

Use `ReqVCR.allow/3` to grant access:

```elixir
ReqVCR.allow(MyApp.ReqStub, self(), spawned_pid)
```

## Limitations

- Cassettes are stored as plain text - don't commit real secrets
- Response bodies are base64-encoded, not human-readable in cassettes
- Redaction is automatic and not currently configurable

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.

## License

Apache 2.0 - see LICENSE file for details.
