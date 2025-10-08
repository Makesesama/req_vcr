# Example: Custom Cassette Organization
#
# This example demonstrates the new cassette organization features in Reqord.
# Run with: mix run examples/custom_cassette_organization.exs

# Example 1: Using vcr_path tag for explicit path control
defmodule Example1.LLMTest do
  use Reqord.Case

  @moduledoc """
  Organize cassettes by provider and model using explicit paths.
  Perfect for LLM testing where you want clear directory structure.
  """

  @tag vcr_path: "providers/google/gemini-2.0-flash/basic_chat"
  @tag vcr_mode: :new_episodes
  test "google gemini basic chat" do
    # Cassette will be at:
    # test/support/cassettes/providers/google/gemini-2.0-flash/basic_chat.jsonl
    assert true
  end

  @tag vcr_path: "providers/openai/gpt-4/streaming_chat"
  @tag vcr_mode: :new_episodes
  test "openai gpt-4 streaming" do
    # Cassette will be at:
    # test/support/cassettes/providers/openai/gpt-4/streaming_chat.jsonl
    assert true
  end
end

# Example 2: Using cassette_path_builder for automatic organization
defmodule Example2.AutoOrganizedTest do
  use Reqord.Case

  @moduledoc """
  Use tags and a path builder function to automatically organize cassettes.
  This is cleaner when you have many tests with the same pattern.
  """

  setup_all do
    # Configure the path builder function
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      provider = context.tags[:provider] || "default"
      model = context.tags[:model] || "default"
      category = context.tags[:category] || "general"

      test_name =
        context.test
        |> Atom.to_string()
        |> String.replace(~r/^test /, "")
        |> String.replace(~r/\s+/, "_")

      "#{provider}/#{model}/#{category}/#{test_name}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)

    :ok
  end

  @tag provider: "google", model: "gemini-flash", category: "text"
  @tag vcr_mode: :new_episodes
  test "generate simple text" do
    # Cassette will be at:
    # test/support/cassettes/google/gemini-flash/text/generate_simple_text.jsonl
    assert true
  end

  @tag provider: "google", model: "gemini-flash", category: "streaming"
  @tag vcr_mode: :new_episodes
  test "stream text generation" do
    # Cassette will be at:
    # test/support/cassettes/google/gemini-flash/streaming/stream_text_generation.jsonl
    assert true
  end

  @tag provider: "openai", model: "gpt-4", category: "vision"
  @tag vcr_mode: :new_episodes
  test "analyze image" do
    # Cassette will be at:
    # test/support/cassettes/openai/gpt-4/vision/analyze_image.jsonl
    assert true
  end
end

# Example 3: Backwards compatible simple naming
defmodule Example3.SimpleTest do
  use Reqord.Case

  @moduledoc """
  The old vcr tag still works for simple cases.
  """

  @tag vcr: "simple/cassette/name"
  @tag vcr_mode: :new_episodes
  test "simple cassette name" do
    # Cassette will be at:
    # test/support/cassettes/simple/cassette/name.jsonl
    assert true
  end

  @tag vcr_mode: :new_episodes
  test "default naming" do
    # Cassette will be at:
    # test/support/cassettes/Simple/default_naming.jsonl
    assert true
  end
end

# Example 4: Priority system demonstration
defmodule Example4.PriorityTest do
  use Reqord.Case

  @moduledoc """
  Demonstrates the priority order of cassette naming strategies.
  """

  setup_all do
    # Set up a path builder
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      "builder/#{context.test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)

    :ok
  end

  @tag vcr_path: "explicit/path"
  @tag vcr: "simple/name"
  @tag vcr_mode: :new_episodes
  test "vcr_path wins" do
    # vcr_path has highest priority
    # Cassette will be at: test/support/cassettes/explicit/path.jsonl
    assert true
  end

  @tag vcr: "simple/name"
  @tag vcr_mode: :new_episodes
  test "builder wins over vcr" do
    # cassette_path_builder has priority over vcr tag
    # Cassette will be at: test/support/cassettes/builder/test_builder_wins_over_vcr.jsonl
    assert true
  end

  @tag vcr: "simple/name"
  @tag vcr_mode: :new_episodes
  test "vcr fallback" do
    # Without vcr_path or builder, vcr tag is used
    # (This example has builder, but shows the concept)
    assert true
  end
end

IO.puts("""

Cassette Organization Examples
================================

Reqord now supports flexible cassette organization with:

1. **vcr_path tag** - Explicit per-test path control
   @tag vcr_path: "providers/google/gemini/basic"

2. **cassette_path_builder** - Function-based automatic organization
   config :reqord, cassette_path_builder: fn context -> ... end

3. **vcr tag** - Simple name override (backwards compatible)
   @tag vcr: "simple/name"

4. **Default** - Auto-generated from module/test name

Priority order: vcr_path > cassette_path_builder > vcr > default

See the examples above for detailed usage patterns!
""")
