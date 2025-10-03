[hex-img]: http://img.shields.io/hexpm/v/reqord.svg

[hexdocs-img]: http://img.shields.io/badge/hexdocs-documentation-brightgreen.svg

# Reqord

[![Hex.pm Version][hex-img]](https://hex.pm/packages/reqord)
[![waffle documentation][hexdocs-img]](https://hexdocs.pm/reqord)

VCR-style HTTP recording and replay for Elixir's [Req](https://hexdocs.pm/req) library, with zero application code changes required.

Reqord integrates seamlessly with `Req.Test` to automatically record HTTP interactions to cassette files and replay them in your tests. Perfect for testing applications that interact with external APIs.

## Features

- **Zero app code changes** - Works entirely through `Req.Test` integration
- **Three modes** - Replay (default), Record, and Auto (record on miss)
- **Smart matching** - Requests matched by method, normalized URL, and body hash
- **Automatic redaction** - Auth headers and query params are automatically redacted
- **Concurrent tests** - Full support for async ExUnit tests with private ownership
- **Spawned processes** - Easy allowance API for Tasks and spawned processes

## Installation

Add `reqord` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req, "~> 0.5"},
    {:reqord, "~> 0.1.0"},
    {:jason, "~> 1.4"}  # Required for default JSON adapter
  ]
end
```

**Note**: `jason` is an optional dependency. If you want to use a different JSON library, configure it as shown in the [Advanced Configuration](#custom-json-library) section.

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

### 2. Use Reqord.Case in your tests

```elixir
defmodule MyApp.APITest do
  use Reqord.Case

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

Reqord supports Ruby VCR-style record modes. Control via environment variable, config, or test tags.

#### Available Modes

- **`:once`** (default) - Strict replay. Use existing cassette, raise on new requests
- **`:new_episodes`** - Append mode. Replay existing, record new requests  
- **`:all`** - Always re-record. Ignores cassette, hits live network
- **`:none`** - Never record. Must have complete cassette

#### Environment Variable

```bash
# Once mode (default) - strict replay
REQORD=once mix test

# New episodes mode - append new recordings
REQORD=new_episodes mix test

# All mode - always re-record everything
REQORD=all API_TOKEN=xxx mix test

# None mode - never record, never hit network
REQORD=none mix test
```

#### Application Config

```elixir
# config/test.exs
config :reqord, default_mode: :once
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
  use Reqord.Case

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
  Reqord.allow(MyApp.ReqStub, self(), task.pid)

  {:ok, response} = Task.await(task)
  assert response.status == 200
end
```

## How It Works

### Request Matching

Reqord matches requests using a deterministic key:

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

**🔒 Reqord ensures secrets never get committed to git** by automatically redacting sensitive data from cassettes.

#### Built-in Redaction

**Auth headers** (→ `<REDACTED>`):
- `authorization`, `x-api-key`, `x-auth-token`, `cookie`, etc.

**Auth query parameters** (→ `<REDACTED>`):
- `token`, `api_key`, `access_token`, `refresh_token`, `jwt`, etc.

**Response body patterns**:
- Bearer tokens → `Bearer <REDACTED>`
- Long alphanumeric strings (32+ chars) → `<REDACTED>`
- GitHub tokens (`ghp_*`) → `<REDACTED>`
- JSON keys containing "token", "key", "secret", "password" → `<REDACTED>`

**Volatile headers** (removed entirely):
- `date`, `server`, `set-cookie`, `request-id`, etc.

#### Custom Redaction (VCR-style)

For app-specific secrets, configure custom filters:

```elixir
# config/test.exs
config :reqord, :filters, [
  {"<API_KEY>", fn -> System.get_env("API_KEY") end},
  {"<SHOPIFY_TOKEN>", fn -> Application.get_env(:my_app, :shopify_token) end}
]
```

These filters apply to headers, query parameters, and response bodies.

## Example Workflow

```bash
# 1. Write your test using Reqord.Case
# 2. Record cassettes (hits live API)
REQORD=record API_TOKEN=xxx mix test --include vcr

# 3. Commit cassettes to git
git add test/support/cassettes/
git commit -m "Add API cassettes"

# 4. Run tests in replay mode (no network calls)
mix test

# 5. Update cassettes when API changes
REQORD=record API_TOKEN=xxx mix test --include vcr
```

## Integration with Req.Test

Reqord works alongside your existing `Req.Test` stubs and expectations:

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

### Configurable Settings

Reqord provides several configuration options to customize its behavior:

```elixir
# config/config.exs
config :reqord,
  # Cassette storage directory
  cassette_dir: "test/support/cassettes",

  # JSON library for encoding/decoding cassettes
  json_library: Reqord.JSON.Jason,

  # Default record mode
  default_mode: :once,

  # Auth parameters to redact from URLs
  auth_params: ~w[token apikey api_key access_token refresh_token jwt bearer password secret],

  # Auth headers to redact
  auth_headers: ~w[authorization auth x-api-key x-auth-token x-access-token cookie],

  # Volatile headers to remove from responses
  volatile_headers: ~w[date server set-cookie request-id x-request-id x-amzn-trace-id],

  # Custom redaction filters
  filters: [
    {"<API_KEY>", fn -> System.get_env("API_KEY") end},
    {"<SHOPIFY_TOKEN>", fn -> Application.get_env(:my_app, :shopify_token) end}
  ]
```

### Custom Cassette Directory

Store cassettes in a different location:

```elixir
# config/test.exs
config :reqord, cassette_dir: "test/vcr_cassettes"
```

### Custom Redaction Lists

Add your own auth parameters and headers to redact:

```elixir
# config/config.exs
config :reqord,
  auth_params: ~w[token apikey api_key my_custom_token],
  auth_headers: ~w[authorization x-api-key x-my-custom-auth],
  volatile_headers: ~w[date server x-trace-id x-my-volatile-header]
```

### Custom JSON Library

By default, Reqord uses Jason for JSON encoding/decoding. You can configure a different JSON library to:

- Use your existing JSON library for consistency across your application
- Take advantage of performance characteristics of different JSON libraries
- Avoid adding Jason as a dependency if you already use another JSON library

```elixir
# config/config.exs
config :reqord, :json_library, MyApp.JSONAdapter
```

Your adapter must implement the `Reqord.JSON` behavior:

```elixir
defmodule MyApp.JSONAdapter do
  @behaviour Reqord.JSON

  @impl Reqord.JSON
  def encode!(data), do: MyJSON.encode!(data)

  @impl Reqord.JSON
  def decode(binary), do: MyJSON.decode(binary)

  @impl Reqord.JSON
  def decode!(binary), do: MyJSON.decode!(binary)
end
```

**Popular JSON libraries you can adapt:**
- `Poison` - Pure Elixir JSON library
- `JSX` - Erlang JSON library
- `jiffy` - Fast NIF-based JSON library

### Custom Default Stub Name

```elixir
defmodule MyApp.APITest do
  use Reqord.Case

  # Override for all tests in this module
  defp default_stub_name, do: MyApp.CustomStub
end
```

### Programmatic Installation

For advanced use cases, you can install VCR manually:

```elixir
setup do
  Reqord.install!(
    name: MyApp.ReqStub,
    cassette: "my_test",
    mode: :replay
  )

  :ok
end
```

## CLI Commands

Reqord provides several Mix tasks to help manage your cassettes:

### `mix reqord.show`

Display cassette contents in a readable format:

```bash
# Show all entries in a cassette
mix reqord.show MyTest/my_test.jsonl

# Filter by URL pattern
mix reqord.show MyTest/my_test.jsonl --grep "/users"

# Filter by HTTP method
mix reqord.show MyTest/my_test.jsonl --method POST

# Show raw JSON
mix reqord.show MyTest/my_test.jsonl --raw

# Decode and pretty-print JSON response bodies
mix reqord.show MyTest/my_test.jsonl --decode-body
```

### `mix reqord.audit`

Audit cassettes for potential issues:

```bash
# Run all audits
mix reqord.audit

# Check for potential secrets only
mix reqord.audit --secrets-only

# Find stale cassettes (older than 90 days)
mix reqord.audit --stale-days 90
```

The audit task reports:
- **Secrets**: Potential sensitive data that should be redacted (tokens, API keys, etc.)
- **Stale cassettes**: Files older than specified days
- **Unused cassettes**: Entries not hit during test runs (requires coverage data)

### `mix reqord.prune`

Clean up cassette files:

```bash
# Preview what would be removed (dry run)
mix reqord.prune --dry-run

# Remove empty cassettes and duplicates
mix reqord.prune

# Remove cassettes older than 180 days
mix reqord.prune --stale-days 180

# Remove only duplicate entries
mix reqord.prune --duplicates-only

# Remove only empty files
mix reqord.prune --empty-only

# Skip confirmation
mix reqord.prune --force
```

### `mix reqord.rename`

Rename or move cassette files:

```bash
# Rename a single cassette
mix reqord.rename old_name.jsonl new_name.jsonl

# Move all cassettes from one module to another
mix reqord.rename --from "OldModule/" --to "NewModule/"

# Preview changes
mix reqord.rename --from "OldModule/" --to "NewModule/" --dry-run

# Migrate cassettes to latest schema (for future schema changes)
mix reqord.rename --migrate
```

## Example API for Testing

This repository includes a test API server (`test_api/`) for demonstrating Reqord's functionality. It's a simple REST API with authentication that's used in the example tests.

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
REQORD=all mix test test/example_api_test.exs
```

See `test_api/README.md` for more details on the test API.

## Troubleshooting

### "No cassette entry found" error

This means you're in `:once` mode but the cassette doesn't have a matching entry.

**Solution**: Record the cassette first:

```bash
REQORD=all mix test
```

Or use new_episodes mode to record on misses:

```bash
REQORD=new_episodes mix test
```

### Tests fail with "No Req.Test stub found"

Make sure you've configured `Req.Test` in your test config and are using the correct stub name.

### Spawned processes can't make requests

Use `Reqord.allow/3` to grant access:

```elixir
Reqord.allow(MyApp.ReqStub, self(), spawned_pid)
```

## Limitations

- Response bodies are base64-encoded, not human-readable in cassettes
- Request matching is based on method + URI by default (configurable via `match_on`)

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.

## License

Apache 2.0 - see LICENSE file for details.
