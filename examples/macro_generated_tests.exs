# Example: Macro-Generated Tests with Reqord
#
# This example demonstrates how to handle macro-generated tests where multiple
# tests share the same name but need different cassettes.

# Example 1: The Problem - Tests sharing cassettes
defmodule Example1.ProblemDemo do
  use Reqord.Case

  @moduledoc """
  This demonstrates the problem: macro-generated tests with the same name
  will share the same cassette.
  """

  for model <- ["model-a", "model-b"] do
    @model model

    describe "#{model}" do
      @tag vcr_mode: :new_episodes
      test "generates text" do
        # ❌ Problem: Both tests have the name "test generates text"
        # They will share: ProblemDemo/generates_text.jsonl
        # This breaks if model-a and model-b give different responses
        IO.puts("Testing #{@model}")
        assert true
      end
    end
  end
end

# Example 2: Simple Solution - Include variable in test name
defmodule Example2.SimpleWorkaround do
  use Reqord.Case

  @moduledoc """
  Simplest solution: Include the variable in the test name itself.
  Works automatically, no configuration needed.
  """

  for model <- ["model-a", "model-b"] do
    @model model

    @tag vcr_mode: :new_episodes
    test "#{model} generates text" do
      # ✓ Test names are unique: "model-a generates text", "model-b generates text"
      # Cassettes: SimpleWorkaround/model-a_generates_text.jsonl
      #            SimpleWorkaround/model-b_generates_text.jsonl
      IO.puts("Testing #{@model}")
      assert true
    end
  end
end

# Example 3: Advanced Solution - set_cassette_context
defmodule Example3.StructuredOrganization do
  use Reqord.Case

  @moduledoc """
  For complex scenarios with multiple variables and structured paths,
  use set_cassette_context with a path builder.
  """

  setup_all do
    # Configure path builder to use macro context
    Application.put_env(:reqord, :cassette_path_builder, fn context ->
      model = get_in(context, [:macro_context, :model]) || "default"
      test = context.test |> Atom.to_string()
      "models/#{model}/#{test}"
    end)

    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)

    :ok
  end

  for model <- ["gpt-4", "gemini-flash"] do
    @model model

    describe "#{model}" do
      setup do
        # Pass compile-time variable to cassette naming
        Reqord.Case.set_cassette_context(%{model: @model})
        :ok
      end

      @tag vcr_mode: :new_episodes
      test "generates text" do
        # ✓ Structured paths: models/gpt-4/test_generates_text.jsonl
        #                     models/gemini-flash/test_generates_text.jsonl
        IO.puts("Testing #{@model}")
        assert true
      end

      @tag vcr_mode: :new_episodes
      test "handles errors" do
        # Each model gets its own cassette for each test
        assert true
      end
    end
  end
end

# Example 4: Real-world LLM Testing
defmodule Example4.LLMProviderTests do
  use Reqord.Case

  @moduledoc """
  Realistic example showing how to test multiple providers and models
  with organized cassette structure.
  """

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

    :ok
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

        @tag vcr_mode: :new_episodes
        test "basic generation" do
          # providers/google/gemini-2.0-flash/test_basic_generation.jsonl
          # providers/google/gemini-1.5-pro/test_basic_generation.jsonl
          # providers/openai/gpt-4/test_basic_generation.jsonl
          # providers/openai/gpt-3.5-turbo/test_basic_generation.jsonl
          IO.puts("Testing #{@provider}:#{@model}")
          assert true
        end

        @tag vcr_mode: :new_episodes
        test "with system prompt" do
          # Each provider/model combination gets separate cassettes
          assert true
        end
      end
    end
  end
end

IO.puts("""

Macro-Generated Test Examples
==============================

Run these examples to see different approaches:

1. Example1 - Shows the problem (tests share cassettes)
2. Example2 - Simple solution (include variable in test name)
3. Example3 - Advanced solution (set_cassette_context + path_builder)
4. Example4 - Real-world LLM testing scenario

Recommendation:
- Use Example2 pattern for simple cases
- Use Example3/4 pattern for complex multi-variable scenarios
""")
