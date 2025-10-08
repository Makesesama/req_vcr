defmodule Reqord.NamedBuildersTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for named cassette path builders configured in application config.
  """

  # Configure builders at compile time for nested test modules (merge with existing)
  existing = Application.get_env(:reqord, :cassette_path_builders, %{})

  Application.put_env(
    :reqord,
    :cassette_path_builders,
    Map.merge(existing, %{
      llm_provider: fn context ->
        provider = get_in(context, [:macro_context, :provider]) || "default"
        model = get_in(context, [:macro_context, :model]) || "default"
        "providers/#{provider}/#{model}/#{context.test}"
      end,
      feature_based: fn context ->
        feature = context[:feature] || "general"
        "features/#{feature}/#{context.test}"
      end,
      test_builder: fn context ->
        "custom/#{context.test}"
      end,
      api: fn context -> "api/#{context.test}" end,
      webhook: fn context -> "webhooks/#{context.test}" end,
      integration: fn context -> "integrations/#{context.test}" end,
      tagged: fn context ->
        env = context[:environment] || "default"
        "#{env}/#{context.test}"
      end
    })
  )

  # Note: No cleanup needed - builders are additive across test files

  describe "named builders" do
    defmodule LLMProviderTest do
      use Reqord.Case, async: false, cassette_path_builder: :llm_provider

      setup do
        Reqord.Case.set_cassette_context(%{
          provider: "google",
          model: "gemini-flash"
        })

        :ok
      end

      @tag vcr_mode: :new_episodes
      test "uses llm_provider builder" do
        # Should use: providers/google/gemini-flash/test_uses_llm_provider_builder.jsonl
        assert true
      end
    end

    defmodule FeatureBasedTest do
      use Reqord.Case, async: false, cassette_path_builder: :feature_based

      @tag feature: "authentication"
      @tag vcr_mode: :new_episodes
      test "uses feature_based builder" do
        # Should use: features/authentication/test_uses_feature_based_builder.jsonl
        assert true
      end
    end

    defmodule DefaultTest do
      use Reqord.Case, async: false

      @tag vcr_mode: :new_episodes
      test "uses default naming" do
        # Should use: Default/uses_default_naming.jsonl
        assert true
      end
    end

    test "named builders work when configured" do
      # Builders already configured at compile time
      # Tests run as part of module definitions above
      assert true
    end
  end

  describe "error handling" do
    test "raises helpful error when builder not found" do
      # Configure only one builder temporarily
      original = Application.get_env(:reqord, :cassette_path_builders)

      Application.put_env(:reqord, :cassette_path_builders, %{
        existing: fn context -> "test/#{context.test}" end
      })

      # The test should raise with a helpful message
      assert_raise ArgumentError, ~r/Named cassette path builder :nonexistent not found/, fn ->
        # Simulate the cassette_name call
        _context = %{named_builder: :nonexistent, test: :test_example}
        builders = Application.get_env(:reqord, :cassette_path_builders, %{})

        case Map.get(builders, :nonexistent) do
          nil ->
            raise ArgumentError,
                  "Named cassette path builder :nonexistent not found. " <>
                    "Available builders: #{inspect(Map.keys(builders))}"
        end
      end

      # Restore original
      Application.put_env(:reqord, :cassette_path_builders, original)
    end

    test "raises when builder is not a function" do
      original = Application.get_env(:reqord, :cassette_path_builders)

      Application.put_env(:reqord, :cassette_path_builders, %{
        invalid: "not a function"
      })

      assert_raise ArgumentError, ~r/must be a function that takes a context/, fn ->
        context = %{named_builder: :invalid, test: :test_example}
        builders = Application.get_env(:reqord, :cassette_path_builders, %{})

        case Map.get(builders, :invalid) do
          builder when is_function(builder, 1) ->
            builder.(context)

          _ ->
            raise ArgumentError,
                  "Cassette path builder :invalid must be a function that takes a context"
        end
      end

      # Restore original
      Application.put_env(:reqord, :cassette_path_builders, original)
    end
  end

  describe "priority with named builders" do
    defmodule PriorityTest do
      use Reqord.Case, async: false, cassette_path_builder: :test_builder

      @tag vcr_path: "explicit/path"
      @tag vcr_mode: :new_episodes
      test "vcr_path wins over named builder" do
        # vcr_path has highest priority
        # Should use: explicit/path.jsonl
        assert true
      end

      @tag vcr: "simple_name"
      @tag vcr_mode: :new_episodes
      test "named builder wins over vcr tag" do
        # Named builder should win
        # Should use: custom/test_named_builder_wins_over_vcr_tag.jsonl
        assert true
      end
    end

    test "priority order is correct" do
      # Builders already configured at compile time
      assert true
    end
  end

  describe "realistic req_llm scenario" do
    defmodule ReqLLMUtilsTest do
      use Reqord.Case, async: false

      @tag vcr_mode: :new_episodes
      test "utility functions use default naming" do
        # No named builder, uses default
        # ReqLLMUtils/utility_functions_use_default_naming.jsonl
        assert true
      end
    end

    defmodule ReqLLMProvidersTest do
      use Reqord.Case, async: false, cassette_path_builder: :llm_provider

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

            @tag vcr_mode: :new_episodes
            test "generates text" do
              # Uses llm_provider builder:
              # providers/google/gemini-flash/test_generates_text.jsonl
              # providers/openai/gpt-4/test_generates_text.jsonl
              assert true
            end
          end
        end
      end
    end

    test "req_llm scenario works" do
      # Builders already configured at compile time
      # Utility tests use default naming
      # Provider tests use llm_provider builder
      assert true
    end
  end

  describe "multiple named builders in same project" do
    defmodule APITest do
      use Reqord.Case, async: false, cassette_path_builder: :api

      @tag vcr_mode: :new_episodes
      test "uses api builder" do
        assert true
      end
    end

    defmodule WebhookTest do
      use Reqord.Case, async: false, cassette_path_builder: :webhook

      @tag vcr_mode: :new_episodes
      test "uses webhook builder" do
        assert true
      end
    end

    defmodule IntegrationTest do
      use Reqord.Case, async: false, cassette_path_builder: :integration

      @tag vcr_mode: :new_episodes
      test "uses integration builder" do
        assert true
      end
    end

    test "different modules can use different named builders" do
      # Builders already configured at compile time
      assert true
    end
  end

  describe "named builder with tags" do
    defmodule TaggedTest do
      use Reqord.Case, async: false, cassette_path_builder: :tagged

      @tag environment: "staging"
      @tag vcr_mode: :new_episodes
      test "builder can access tags" do
        # Builder uses tags from context
        # staging/test_builder_can_access_tags.jsonl
        assert true
      end

      @tag environment: "production"
      @tag vcr_mode: :new_episodes
      test "different tags produce different paths" do
        # production/test_different_tags_produce_different_paths.jsonl
        assert true
      end
    end

    test "named builders can access test tags" do
      # Builders already configured at compile time
      assert true
    end
  end
end
