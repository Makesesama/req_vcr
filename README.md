[hex-img]: http://img.shields.io/hexpm/v/reqord.svg

[hexdocs-img]: http://img.shields.io/badge/hexdocs-documentation-brightgreen.svg

# Reqord

[![Hex.pm Version][hex-img]](https://hex.pm/packages/reqord)
[![waffle documentation][hexdocs-img]](https://hexdocs.pm/reqord)

VCR-style HTTP recording and replay for Elixir's [Req](https://hexdocs.pm/req) library. Record HTTP interactions once, replay them in tests forever—no external dependencies, fast tests, deterministic results.

## Features

- **Zero app code changes** - Works through `Req.Test` integration
- **Fast tests** - Replay from cassettes, no network calls
- **Chronological ordering** - Timestamp-based replay for concurrent requests
- **Four modes** - Replay (default), Record new, Auto-record, Re-record all
- **Binary & streaming** - Handles images, PDFs, SSE, chunked responses
- **Flexible organization** - Named builders, custom paths, macro support
- **Test-friendly** - Works with async tests and spawned processes

## Quick Start

### Installation

```elixir
def deps do
  [
    {:req, "~> 0.5"},
    {:reqord, "~> 0.3.0"}
  ]
end
```

### Basic Usage

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

### Record Cassettes

```bash
# Record on first run
REQORD=new_episodes mix test

# Subsequent runs replay from cassettes (no network calls)
mix test
```

**That's it!** Your tests now use recorded cassettes. 🎉

## Recording Modes

Control how Reqord handles cassettes:

| Mode | Environment Variable | Behavior |
|------|---------------------|----------|
| **Replay** | `REQORD=none` (default) | Use cassettes, never hit network |
| **Record new** | `REQORD=new_episodes` | Replay existing, record new requests |
| **Strict** | `REQORD=once` | Replay only, raise on missing cassettes |
| **Re-record** | `REQORD=all` | Always hit network, re-record everything |

### Per-Test Mode

```elixir
@tag vcr_mode: :new_episodes
test "can record new requests" do
  # This test can record even if REQORD=none globally
end
```

## Cassette Organization

### Default: Module/Test Name

```elixir
defmodule MyApp.UserAPITest do
  use Reqord.Case

  test "creates user" do
    # Cassette: test/support/cassettes/UserAPI/creates_user.jsonl
  end
end
```

### Custom Name

```elixir
@tag vcr: "my_custom_name"
test "example" do
  # Cassette: test/support/cassettes/my_custom_name.jsonl
end
```

### Named Builders (Recommended for Complex Projects)

```elixir
# config/test.exs
config :reqord,
  cassette_path_builders: %{
    api: fn context -> "api/#{context.test}" end,
    llm: fn context ->
      provider = get_in(context, [:macro_context, :provider])
      "providers/#{provider}/#{context.test}"
    end
  }

# In tests
defmodule APITest do
  use Reqord.Case, cassette_path_builder: :api
end

defmodule LLMTest do
  use Reqord.Case, cassette_path_builder: :llm
end
```

## Documentation

### Guides

- **[Getting Started](docs/GETTING_STARTED.md)** - Installation and basic usage
- **[Security](docs/SECURITY.md)** - Redacting secrets and keeping cassettes safe
- **[Advanced Configuration](docs/ADVANCED_CONFIGURATION.md)** - Matchers, binary data, streaming, etc.
- **[Cassette Organization](docs/CASSETTE_ORGANIZATION.md)** - Named builders, custom paths, patterns
- **[Macro Support](docs/MACRO_SUPPORT.md)** - Handle macro-generated tests
- **[File Management](docs/FILE_MANAGEMENT.md)** - Cassette format and storage

### Common Tasks

#### Concurrent Requests

```elixir
test "handles parallel requests" do
  task = Task.async(fn ->
    Req.get("https://api.example.com/data")
  end)

  Reqord.allow(MyApp.ReqStub, self(), task.pid)
  {:ok, response} = Task.await(task)
end
```

#### Custom Matchers

```elixir
# Match on method, path, and body
@tag match_on: [:method, :path, :body]
test "strict matching" do
  Req.post(url, json: %{name: "Alice"})
end
```

#### Binary Data

Reqord automatically handles binary responses:

```elixir
test "downloads image" do
  {:ok, resp} = Req.get("https://example.com/image.png")
  # Large binaries stored externally, replayed seamlessly
end
```

#### Streaming Responses

```elixir
test "handles server-sent events" do
  {:ok, resp} = Req.get("https://api.example.com/stream")
  # Streaming responses captured and replayed
end
```

## Configuration

```elixir
# config/test.exs
config :reqord,
  default_mode: :none,
  cassette_dir: "test/support/cassettes",
  match_on: [:method, :uri]
```

See [Advanced Configuration](docs/ADVANCED_CONFIGURATION.md) for all options.

## How It Works

1. **First run**: Reqord records HTTP requests/responses to cassette files (JSONL format)
2. **Subsequent runs**: Requests are matched against cassettes and responses replayed
3. **Matching**: By default, matches on HTTP method + URI (configurable)
4. **Ordering**: Timestamp-based chronological replay handles concurrent requests

### Request Matching

```
GET https://api.example.com/users?sort=name
↓
Normalized: GET https://api.example.com/users?sort=name (params sorted)
↓
Match cassette entry by: method + normalized URI + body hash
↓
Replay recorded response
```

### Cassette Format

Cassettes are stored as JSON Lines (`.jsonl`):

```jsonl
{"req":{"method":"GET","url":"..."},"resp":{"status":200,"body":"..."},"recorded_at":"2024-01-01T12:00:00.000000Z"}
{"req":{"method":"POST","url":"..."},"resp":{"status":201,"body":"..."},"recorded_at":"2024-01-01T12:00:01.123456Z"}
```

## Comparison with ExVCR

| Feature | Reqord | ExVCR |
|---------|--------|-------|
| **Best for** | API clients built on Req | Full-fledged apps with various HTTP libraries |
| **HTTP clients** | Req only | HTTPoison, HTTPotion, Hackney, and more |
| **Integration** | Req.Test (no code changes) | Wrap HTTP calls with `use_cassette` |
| **Binary data** | External storage for large files | Inline Base64 encoding |
| **Streaming** | Full SSE/chunked response support | Standard request/response pairs |
| **Cassette writes** | Async (non-blocking) | Synchronous |

**Choose Reqord if:** You're building an API client or library using Req and want zero application code changes.

**Choose ExVCR if:** You need to support multiple HTTP clients in a full application or use libraries other than Req.

## Examples

Check out the `examples/` directory for complete examples:

- `examples/macro_generated_tests.exs` - Macro-generated test patterns
- More examples in the documentation guides

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Inspired by [ExVCR](https://github.com/parroty/exvcr) and Ruby's [VCR](https://github.com/vcr/vcr).
