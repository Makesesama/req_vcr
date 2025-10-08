# Macro-Generated Test Support

Reqord supports macro-generated tests where compile-time variables need to be included in cassette naming.

## The Problem

When you generate multiple tests in a loop using the same test name, they all share the same cassette:

```elixir
for model <- ["gpt-4", "gemini-flash"] do
  @model model

  describe "#{model}" do
    test "generates text" do
      # Problem: All iterations have the same test name
      # Result: All models share one cassette file
      # This breaks when different models give different responses
    end
  end
end
```

Why this happens:
- ExUnit creates separate tests, but they all have the name `"test generates text"`
- Reqord's cassette naming uses: `"#{ModuleName}/#{test_name}"`
- The `describe` block name is not included by default
- Result: `MyTest/generates_text.jsonl` for all models

## The Solution

Use `Reqord.Case.set_cassette_context/1` with a `:cassette_path_builder`:

```elixir
defmodule MyLLMTest do
  use Reqord.Case

  # 1. Configure path builder to use macro context
  setup_all do
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      model = get_in(context, [:macro_context, :model]) || "default"
      test = context.test |> Atom.to_string()
      "models/#{model}/#{test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)
  end

  # 2. Set context in setup for each iteration
  for model <- ["gpt-4", "gemini-flash"] do
    @model model

    describe "#{model}" do
      setup do
        Reqord.Case.set_cassette_context(%{model: @model})
        :ok
      end

      test "generates text" do
        # Now each model gets its own cassette:
        # models/gpt-4/test_generates_text.jsonl
        # models/gemini-flash/test_generates_text.jsonl
      end
    end
  end
end
```

## How It Works

1. Call `set_cassette_context/1` in your `setup` block with compile-time variables
2. Reqord merges this into `context.macro_context`
3. Your `:cassette_path_builder` accesses it via `get_in(context, [:macro_context, :key])`
4. Context is automatically cleaned up after each test

## Complete Example

```elixir
defmodule MyApp.ProviderTest do
  use Reqord.Case

  setup_all do
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      provider = get_in(context, [:macro_context, :provider]) || "default"
      model = get_in(context, [:macro_context, :model]) || "default"
      test = context.test |> Atom.to_string()
      "providers/#{provider}/#{model}/#{test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)
  end

  @providers %{
    google: ["gemini-2.0-flash", "gemini-1.5-pro"],
    openai: ["gpt-4", "gpt-3.5-turbo"]
  }

  for {provider, models} <- @providers do
    @provider provider

    for model <- models do
      @model model

      describe "#{provider}:#{model}" do
        setup do
          Reqord.Case.set_cassette_context(%{
            provider: Atom.to_string(@provider),
            model: @model
          })
          :ok
        end

        test "generates text" do
          # providers/google/gemini-2.0-flash/test_generates_text.jsonl
          # providers/google/gemini-1.5-pro/test_generates_text.jsonl
          # providers/openai/gpt-4/test_generates_text.jsonl
          # providers/openai/gpt-3.5-turbo/test_generates_text.jsonl
        end
      end
    end
  end
end
```

## Best Practices

### 1. Always use `get_in/2` with defaults

```elixir
# Good - handles missing macro_context gracefully
model = get_in(context, [:macro_context, :model]) || "default"

# Bad - crashes if macro_context doesn't exist
model = context.macro_context[:model] || "default"
```

### 2. Keep context simple

```elixir
# Good - flat structure
set_cassette_context(%{
  provider: "google",
  model: "gemini-flash"
})

# Avoid - nested structures
set_cassette_context(%{
  llm: %{provider: %{name: "google"}}
})
```

### 3. Support both macro context and tags

```elixir
cassette_path_builder: fn context ->
  # Try macro context first, fall back to tags
  model = get_in(context, [:macro_context, :model]) || context.tags[:model] || "default"
  "models/#{model}/#{context.test}"
end
```

## Alternative: Use test names with variables

If you only need simple cases, include the variable in the test name:

```elixir
for model <- ["gpt-4", "gemini-flash"] do
  @model model

  test "#{model} generates text" do
    # Each test has a unique name automatically:
    # MyTest/gpt-4_generates_text.jsonl
    # MyTest/gemini-flash_generates_text.jsonl
  end
end
```

This works automatically without any configuration, but gives you less control over cassette organization.

## When to Use This Feature

Use `set_cassette_context` when:
- ✅ You have macro-generated tests with the same test name
- ✅ You need structured cassette paths (provider/model/test)
- ✅ You're working with multiple compile-time variables

Don't use it when:
- ❌ Test names are already unique (include the variable in the test name)
- ❌ Simple default naming works for your use case
- ❌ You only have a few tests (use `@tag vcr_path:` instead)

## API Reference

### `Reqord.Case.set_cassette_context/1`

Sets cassette context for the current test process.

```elixir
@spec set_cassette_context(map()) :: :ok
```

**Example:**
```elixir
setup do
  Reqord.Case.set_cassette_context(%{
    provider: "google",
    model: @model
  })
  :ok
end
```

The context is automatically:
- Merged into `context.macro_context` for use by `:cassette_path_builder`
- Cleaned up after each test

## See Also

- [Cassette Organization Guide](CASSETTE_ORGANIZATION.md) - All cassette naming strategies
- [Examples](examples/macro_generated_tests.exs) - Working code examples
