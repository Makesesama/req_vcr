# Cassette Organization Guide

Reqord now supports flexible cassette organization to help you structure your test fixtures in a way that makes sense for your project.

## Overview

Reqord provides four strategies for organizing cassettes, with the following priority order:

1. **`:vcr_path` tag** - Explicit per-test path (highest priority)
2. **`:cassette_path_builder` config** - Function-based automatic organization
3. **`:vcr` tag** - Simple name override (backwards compatible)
4. **Default behavior** - Auto-generated from module and test name (lowest priority)

## Strategy 1: Explicit Path with `:vcr_path` tag

Use the `:vcr_path` tag when you need explicit control over cassette placement for specific tests.

```elixir
defmodule MyApp.LLMTest do
  use Reqord.Case

  @tag vcr_path: "providers/google/gemini-2.0-flash/basic_chat"
  test "google gemini basic chat" do
    # Cassette: test/support/cassettes/providers/google/gemini-2.0-flash/basic_chat.jsonl
  end

  @tag vcr_path: "providers/openai/gpt-4/streaming"
  test "openai gpt-4 streaming" do
    # Cassette: test/support/cassettes/providers/openai/gpt-4/streaming.jsonl
  end
end
```

**Best for:**
- One-off custom paths
- Overriding automatic organization for specific tests
- Maximum control

## Strategy 2: Automatic Organization with `:cassette_path_builder`

Configure functions to automatically organize cassettes based on test context. You can use **named builders** (recommended) or configure globally/per-module.

### Named Builders (Recommended)

Define reusable builders in config and reference them by name in test modules:

```elixir
# config/test.exs
config :reqord,
  cassette_path_builders: %{
    llm_provider: fn context ->
      provider = get_in(context, [:macro_context, :provider]) || "default"
      model = get_in(context, [:macro_context, :model]) || "default"
      "providers/#{provider}/#{model}/#{context.test}"
    end,
    feature: fn context ->
      feature = context[:feature] || "general"
      "features/#{feature}/#{context.test}"
    end,
    api: fn context ->
      "api/#{context.test}"
    end
  }
```

Then use them in your test modules:

```elixir
# LLM tests use the llm_provider builder
defmodule MyApp.LLMTest do
  use Reqord.Case, cassette_path_builder: :llm_provider

  for {provider, models} <- [{"google", ["gemini-flash"]}, {"openai", ["gpt-4"]}] do
    @provider provider
    for model <- models do
      @model model

      describe "#{provider}:#{model}" do
        setup do
          Reqord.Case.set_cassette_context(%{
            provider: @provider,
            model: @model
          })
          :ok
        end

        test "generates text" do
          # providers/google/gemini-flash/test_generates_text.jsonl
          # providers/openai/gpt-4/test_generates_text.jsonl
        end
      end
    end
  end
end

# API tests use the api builder
defmodule MyApp.APITest do
  use Reqord.Case, cassette_path_builder: :api

  test "fetches data" do
    # api/test_fetches_data.jsonl
  end
end

# Utility tests use default naming (no builder specified)
defmodule MyApp.UtilsTest do
  use Reqord.Case

  test "helper function" do
    # Utils/helper_function.jsonl
  end
end
```

### Global Configuration

Configure a single builder for all tests:

```elixir
# config/test.exs
config :reqord,
  cassette_path_builder: fn context ->
    provider = context[:provider] || "default"
    model = context[:model] || "default"
    "#{provider}/#{model}/#{context.test}"
  end
```

Then use tags in your tests:

```elixir
defmodule MyApp.LLMTest do
  use Reqord.Case

  @tag provider: "google", model: "gemini-2.0-flash"
  test "basic chat" do
    # Cassette: test/support/cassettes/google/gemini-2.0-flash/test_basic_chat.jsonl
  end

  @tag provider: "openai", model: "gpt-4"
  test "streaming response" do
    # Cassette: test/support/cassettes/openai/gpt-4/test_streaming_response.jsonl
  end
end
```

### Scoped Configuration (Per-Module or Per-Describe)

For projects with mixed organization needs (like req_llm), you can scope the path builder to specific modules or describe blocks:

```elixir
# General utility tests use default naming
defmodule MyApp.UtilsTest do
  use Reqord.Case

  test "helper function works" do
    # Uses default: test/support/cassettes/Utils/helper_function_works.jsonl
  end
end

# LLM provider tests use custom organization
defmodule MyApp.LLMProviderTest do
  use Reqord.Case

  setup_all do
    # Configure path builder for this module only
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      provider = get_in(context, [:macro_context, :provider]) || "default"
      model = get_in(context, [:macro_context, :model]) || "default"
      "providers/#{provider}/#{model}/#{context.test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)
  end

  for {provider, models} <- [{"google", ["gemini-flash"]}, {"openai", ["gpt-4"]}] do
    @provider provider

    for model <- models do
      @model model

      describe "#{provider}:#{model}" do
        setup do
          Reqord.Case.set_cassette_context(%{
            provider: @provider,
            model: @model
          })
          :ok
        end

        test "generates text" do
          # providers/google/gemini-flash/test_generates_text.jsonl
          # providers/openai/gpt-4/test_generates_text.jsonl
        end
      end
    end
  end
end
```

You can also scope to specific describe blocks:

```elixir
defmodule MyApp.MixedTest do
  use Reqord.Case

  describe "feature A" do
    setup do
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        "feature_a/#{context.test}"
      end)

      on_exit(fn ->
        Application.delete_env(:reqord, :cassette_path_builder)
      end)
      :ok
    end

    test "does something" do
      # feature_a/test_does_something.jsonl
    end
  end

  describe "feature B" do
    setup do
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        "feature_b/#{context.test}"
      end)

      on_exit(fn ->
        Application.delete_env(:reqord, :cassette_path_builder)
      end)
      :ok
    end

    test "does something else" do
      # feature_b/test_does_something_else.jsonl
    end
  end
end
```

**Best for:**
- Projects with multiple test modules needing different organization strategies (**use named builders**)
- LLM testing with multiple providers/models (**use named builders**)
- Projects with mixed organization needs (some modules need custom paths, others use defaults)
- Consistent organization across many tests
- Per-module or per-feature organization

### Context Available to Path Builder

The `context` map passed to your path builder function contains:

- `context.test` - Test name as an atom (e.g., `:test_basic_chat`)
- `context.module` - Test module name (e.g., `MyApp.LLMTest`)
- `context.tags` - Map of all test tags (e.g., `%{provider: "google", model: "gpt-4"}`)
- Any other ExUnit context values

## Strategy 3: Simple Name Override with `:vcr` tag

The traditional approach for custom cassette names (backwards compatible).

```elixir
defmodule MyApp.APITest do
  use Reqord.Case

  @tag vcr: "custom/cassette/name"
  test "api call" do
    # Cassette: test/support/cassettes/custom/cassette/name.jsonl
  end
end
```

**Best for:**
- Simple custom names
- Backwards compatibility
- Quick overrides without complex logic

## Strategy 4: Default Behavior

If none of the above are specified, Reqord uses the module and test name.

```elixir
defmodule MyApp.UserAPITest do
  use Reqord.Case

  test "fetches user list" do
    # Cassette: test/support/cassettes/UserAPI/fetches_user_list.jsonl
  end
end
```

**Best for:**
- Simple projects
- When you don't need custom organization
- Getting started quickly

## Priority System

When multiple strategies are configured, Reqord uses this priority order:

```elixir
# Highest priority
@tag vcr_path: "explicit/path"           # ← Always wins

# Medium-high priority
# Named builder via use Reqord.Case, cassette_path_builder: :name
# OR per-module/describe via setup_all/setup + Application.put_env
# OR global via config :reqord, cassette_path_builder: fn context -> ... end
# (Named builder > scoped builder > global builder)

# Medium priority
@tag vcr: "simple/name"

# Lowest priority (fallback)
# Default: "ModuleName/test_name"
```

Example demonstrating priority:

```elixir
# With cassette_path_builder configured
config :reqord,
  cassette_path_builder: fn context ->
    "builder/#{context.test}"
  end

# In your test
@tag vcr_path: "explicit/path"  # ← This wins
@tag vcr: "simple/name"         # ← Ignored
test "example" do
  # Uses: test/support/cassettes/explicit/path.jsonl
end
```

### Named Builders vs Scoped Builders

**Named builders (recommended)** provide a cleaner way to assign different cassette organization to different test modules:

```elixir
# config/test.exs
config :reqord,
  cassette_path_builders: %{
    custom: fn context -> "custom/#{context.test}" end
  }

# Module A uses default naming
defmodule MyApp.ModuleATest do
  use Reqord.Case

  test "example" do
    # Uses: ModuleA/example.jsonl
  end
end

# Module B uses named builder
defmodule MyApp.ModuleBTest do
  use Reqord.Case, cassette_path_builder: :custom

  test "example" do
    # Uses: custom/test_example.jsonl
  end
end
```

**Scoped builders** (via setup_all) are still supported but less convenient:

```elixir
# Module B uses scoped builder
defmodule MyApp.ModuleBTest do
  use Reqord.Case

  setup_all do
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      "custom/#{context.test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)
  end

  test "example" do
    # Uses: custom/test_example.jsonl
  end
end
```

## Common Patterns

### Pattern 1: Provider/Model Organization

Perfect for LLM testing or multi-provider APIs:

```elixir
# config/test.exs
config :reqord,
  cassette_path_builder: fn context ->
    provider = context.tags[:provider] || "default"
    model = context.tags[:model] || "default"
    test = context.test |> Atom.to_string()
    "#{provider}/#{model}/#{test}"
  end
```

### Pattern 2: Feature/Category Organization

Group cassettes by feature area:

```elixir
config :reqord,
  cassette_path_builder: fn context ->
    category = context.tags[:category] || "general"
    module = context.module |> Module.split() |> List.last()
    test = context.test |> Atom.to_string()
    "#{category}/#{module}/#{test}"
  end
```

### Pattern 3: Environment-based Organization

Separate cassettes by environment:

```elixir
config :reqord,
  cassette_path_builder: fn context ->
    env = context.tags[:env] || "production"
    test = context.test |> Atom.to_string()
    "#{env}/#{test}"
  end
```

## Migration from Fixed Structure

If you're migrating from a fixed cassette structure, you can use both approaches during transition:

```elixir
# New tests use path builder
@tag provider: "google", model: "gemini"
test "new test" do
  # Uses: google/gemini/new_test.jsonl
end

# Old tests keep explicit paths
@tag vcr_path: "legacy/old_cassette"
test "old test" do
  # Uses: legacy/old_cassette.jsonl
end
```

## Macro-Generated Tests

When generating multiple tests in a loop with the same test name, they will share the same cassette by default. There are two solutions:

### Solution 1: Include Variable in Test Name (Simplest)

```elixir
for model <- ["gpt-4", "gemini-flash"] do
  @model model

  test "#{model} generates text" do
    # Test names are unique, cassettes are automatically unique:
    # MyTest/gpt-4_generates_text.jsonl
    # MyTest/gemini-flash_generates_text.jsonl
  end
end
```

**Pros:** Works automatically, no configuration needed
**Cons:** Less control over cassette structure

### Solution 2: Use `set_cassette_context` (For Complex Cases)

For structured organization with multiple variables, use `set_cassette_context` with a path builder:

```elixir
defmodule MyLLMTest do
  use Reqord.Case

  setup_all do
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      provider = get_in(context, [:macro_context, :provider]) || "default"
      model = get_in(context, [:macro_context, :model]) || "default"
      "#{provider}/#{model}/#{context.test}"
    end)

    on_exit(fn -> Application.delete_env(:reqord, :cassette_path_builder) end)
  end

  for model <- ["gpt-4", "gemini-flash"] do
    @model model

    describe "#{model}" do
      setup do
        Reqord.Case.set_cassette_context(%{
          provider: "openai",
          model: @model
        })
        :ok
      end

      test "generates text" do
        # openai/gpt-4/test_generates_text.jsonl
        # openai/gemini-flash/test_generates_text.jsonl
      end
    end
  end
end
```

**Pros:** Full control over cassette structure, supports multiple variables
**Cons:** Requires setup code

See [MACRO_SUPPORT.md](MACRO_SUPPORT.md) for complete details and examples.

## Tips

1. **Keep it simple**: Start with the default behavior, add custom organization only when needed
2. **Use named builders**: For projects with multiple organization strategies, define named builders in config instead of using scoped builders - it's cleaner and more maintainable
3. **Be consistent**: Pick one strategy per project/module for easier maintenance
4. **Use tags wisely**: Tag names should be descriptive and match your domain (`:provider`, `:model`, `:feature`, etc.)
5. **Test your builder**: Path builder functions run at test time, so test them thoroughly
6. **Avoid deep nesting**: Limit directory depth to 3-4 levels for better organization
7. **Macro tests**: Use `set_cassette_context/1` for macro-generated tests with compile-time variables
8. **Scoped builders**: Named builders are preferred, but you can use `setup_all` with `Application.put_env` if needed
9. **Always clean up**: When using scoped builders, always use `on_exit` to clean up the Application config

## Examples

See `examples/custom_cassette_organization.exs` for complete working examples of all strategies.
