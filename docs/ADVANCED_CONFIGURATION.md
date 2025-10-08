# Advanced Configuration

This guide covers advanced Reqord features for complex testing scenarios.

## Configuration Options

Configure Reqord in your `config/test.exs`:

```elixir
config :reqord,
  # Default recording mode
  default_mode: :none,

  # Cassette directory
  cassette_dir: "test/support/cassettes",

  # Request matching strategy
  match_on: [:method, :uri],

  # Binary storage configuration
  max_inline_size: 1_048_576,  # 1MB
  binary_storage: :auto,        # :auto, :inline, :external
  object_directory: "test/support/cassettes/objects",

  # Stream replay speed
  stream_speed: :instant  # :instant, :realtime
```

## Request Matching

Control how Reqord matches requests to cassettes:

### Default Matching (Method + URI)

By default, Reqord matches on HTTP method and full URI:

```elixir
test "default matching" do
  # These match the same cassette entry:
  Req.get("https://api.example.com/users")
  Req.get("https://api.example.com/users")  # Replays from cassette
end
```

### Custom Matchers

Override matchers globally or per-test:

```elixir
# Global configuration
config :reqord, match_on: [:method, :path, :body]

# Per-test override
@tag match_on: [:method, :path, :query, :body]
test "strict matching" do
  # Matches on method, path, query params, and request body
end
```

Available matchers:
- `:method` - HTTP method (GET, POST, etc.)
- `:uri` - Full URI including query params
- `:path` - URL path only
- `:query` - Query parameters only
- `:body` - Request body
- `:headers` - Request headers
- `:host` - Hostname
- `:port` - Port number

### Body Matching

Match on request body for POST/PUT requests:

```elixir
@tag match_on: [:method, :uri, :body]
test "body matching" do
  # Different bodies = different cassette entries
  Req.post(url, json: %{name: "Alice"})
  Req.post(url, json: %{name: "Bob"})
end
```

## Custom Stub Names

Override the default Req.Test stub name:

```elixir
defmodule MyTest do
  use Reqord.Case

  @tag req_stub_name: MyApp.CustomStub
  test "with custom stub" do
    # Uses MyApp.CustomStub instead of default
  end
end
```

## Spawned Processes

If your test spawns processes that make HTTP requests, allow them explicitly:

```elixir
test "concurrent requests" do
  task = Task.async(fn ->
    Req.get("https://api.example.com/data")
  end)

  # Allow the task's process to use the stub
  Reqord.allow(MyApp.ReqStub, self(), task.pid)

  {:ok, response} = Task.await(task)
  assert response.status == 200
end
```

## Binary Data Handling

Reqord automatically handles binary responses (images, PDFs, etc.):

### Automatic Storage

```elixir
test "handles binary data" do
  # Large binary responses are automatically stored externally
  {:ok, resp} = Req.get("https://example.com/large-file.pdf")
  assert byte_size(resp.body) > 1_000_000
end
```

### Storage Configuration

```elixir
config :reqord,
  # Size threshold for external storage
  max_inline_size: 1_048_576,  # 1MB

  # Storage strategy
  binary_storage: :auto,  # :auto (smart), :inline (in cassette), :external (separate files)

  # Object storage directory
  object_directory: "test/support/cassettes/objects"
```

## Streaming Responses

Reqord supports streaming responses (Server-Sent Events, chunked transfer):

```elixir
test "handles streaming" do
  {:ok, resp} = Req.get("https://api.example.com/stream",
    into: fn {:data, data}, {req, resp} ->
      # Process streamed data
      {:cont, {req, update_in(resp.body, &(&1 <> data))}}
    end
  )

  assert resp.body =~ "streamed content"
end
```

Configure replay speed:

```elixir
config :reqord,
  stream_speed: :instant  # Replay instantly (default)
  # stream_speed: :realtime  # Replay at original speed
```

## Cassette Organization

For advanced cassette organization strategies, see:
- **[Cassette Organization Guide](CASSETTE_ORGANIZATION.md)** - Named builders, custom paths, etc.
- **[Macro Support Guide](MACRO_SUPPORT.md)** - Macro-generated tests

### Quick Example: Named Builders

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

# test file
defmodule APITest do
  use Reqord.Case, cassette_path_builder: :api
  # Cassettes: api/test_name.jsonl
end

defmodule LLMTest do
  use Reqord.Case, cassette_path_builder: :llm
  # Cassettes: providers/google/test_name.jsonl
end
```

## Application Configuration

Set default mode in your config files:

```elixir
# config/test.exs
config :reqord, default_mode: :none

# config/dev.exs (for development testing)
config :reqord, default_mode: :new_episodes
```

## Cleaning Up Old Cassettes

Reqord provides mix tasks for cassette management:

```bash
# Remove unused cassettes
mix reqord.prune

# Rename cassettes after test refactoring
mix reqord.rename old_name new_name
```

## Debugging

Enable detailed logging:

```elixir
config :logger, level: :debug
```

Check cassette contents:

```bash
# Cassettes are JSON Lines format
cat test/support/cassettes/MyTest/my_test.jsonl | jq
```

## Performance Tips

1. **Use `:none` mode in CI** - Fast, deterministic tests
2. **Group related requests** - One test per logical operation
3. **Use named builders** - Cleaner organization for large projects
4. **Prune regularly** - Remove unused cassettes
5. **External storage** - Keep cassettes small for large binary responses

## See Also

- [Getting Started](GETTING_STARTED.md) - Basic usage
- [Cassette Organization](CASSETTE_ORGANIZATION.md) - Organize cassettes for complex projects
- [Macro Support](MACRO_SUPPORT.md) - Handle macro-generated tests
- [File Management](FILE_MANAGEMENT.md) - Cassette file format and management
