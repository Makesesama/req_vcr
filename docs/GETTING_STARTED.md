# Getting Started with Reqord

Reqord is a VCR-style HTTP testing library for Elixir that works with the Req HTTP client. It records HTTP interactions and replays them in tests, making your tests fast, deterministic, and independent of external services.

## Installation

Add `reqord` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reqord, "~> 0.4.0"}
  ]
end
```

## Basic Usage

### 1. Use Reqord.Case in Your Tests

Replace `use ExUnit.Case` with `use Reqord.Case`:

```elixir
defmodule MyApp.APITest do
  use Reqord.Case  # Instead of: use ExUnit.Case

  test "fetches user data" do
    {:ok, response} = Req.get("https://api.example.com/users/1")

    assert response.status == 200
    assert response.body["name"] == "John Doe"
  end
end
```

### 2. Run Your Tests

On the first run, Reqord will record HTTP requests:

```bash
REQORD=new_episodes mix test
```

This creates a cassette file at `test/support/cassettes/API/fetches_user_data.jsonl` containing the recorded HTTP interaction.

### 3. Subsequent Runs Use Cassettes

On future runs, tests replay from cassettes (no real HTTP calls):

```bash
mix test
```

Your tests are now fast, deterministic, and work offline!

## Security: Keeping Secrets Safe

**Important**: Reqord automatically redacts sensitive data to keep your secrets safe!

Common auth parameters are **automatically redacted** in cassettes:
- Query params: `token`, `apikey`, `password`, `secret`
- Headers: `Authorization`, `X-API-Key`, `Cookie`

```elixir
# Your code:
Req.get("https://api.example.com/data?apikey=secret123")

# Cassette stores:
# url: "https://api.example.com/data?apikey=[REDACTED]"
```

**Best Practice**: Always use environment variables for API keys:

```elixir
test "api call" do
  api_key = System.get_env("API_KEY") || "[REDACTED]"
  Req.get(url, auth: {:bearer, api_key})
end
```

Before committing new cassettes, review them:

```bash
# Check for any leaked secrets
git diff test/support/cassettes/
```

See **[Security Guide](SECURITY.md)** for advanced redaction and best practices.

## Recording Modes

Control how Reqord handles cassettes using the `REQORD` environment variable:

- **`REQORD=none`** (default) - Replay only, never hit network
- **`REQORD=new_episodes`** - Replay existing, record new requests
- **`REQORD=once`** - Strict replay, raise error on new requests
- **`REQORD=all`** - Always hit network and re-record everything

## Common Patterns

### Custom Cassette Names

```elixir
@tag vcr: "my_custom_name"
test "example" do
  # Cassette: test/support/cassettes/my_custom_name.jsonl
end
```

### Per-Test Recording Mode

```elixir
@tag vcr_mode: :new_episodes
test "can record new requests" do
  # This test can record even if REQORD=none
end
```

### Multiple Requests in One Test

Reqord automatically handles multiple HTTP requests in a single test:

```elixir
test "creates and fetches user" do
  # First request - POST
  {:ok, create_resp} = Req.post("https://api.example.com/users",
    json: %{name: "Jane"})
  user_id = create_resp.body["id"]

  # Second request - GET
  {:ok, fetch_resp} = Req.get("https://api.example.com/users/#{user_id}")
  assert fetch_resp.body["name"] == "Jane"
end
```

## Next Steps

- **[Security Guide](SECURITY.md)** - Redacting secrets and keeping cassettes safe
- **[Advanced Configuration](ADVANCED_CONFIGURATION.md)** - Custom cassette organization, matchers, and more
- **[Cassette Organization](CASSETTE_ORGANIZATION.md)** - Organize cassettes for complex projects
- **[Macro Support](MACRO_SUPPORT.md)** - Handle macro-generated tests

## Quick Reference

```elixir
# Basic test
defmodule MyTest do
  use Reqord.Case

  test "api call" do
    {:ok, resp} = Req.get("https://api.example.com/data")
    assert resp.status == 200
  end
end
```

```bash
# Record new cassettes
REQORD=new_episodes mix test

# Re-record everything
REQORD=all mix test

# Replay only (default)
mix test
```

That's it! You're ready to use Reqord in your tests.
