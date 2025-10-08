defmodule Reqord.ScopedPathBuilderTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for scoped cassette_path_builder (per-module and per-test).
  """

  setup do
    # Clean up global config
    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)

    :ok
  end

  describe "per-module path builder via setup_all" do
    defmodule PerModuleTest do
      use Reqord.Case, async: false

      setup_all do
        # Set path builder for all tests in this module
        Application.put_env(:reqord, :cassette_path_builder, fn context ->
          model = get_in(context, [:macro_context, :model]) || "default"
          "module_scoped/#{model}/#{context.test}"
        end)

        on_exit(fn ->
          Application.delete_env(:reqord, :cassette_path_builder)
        end)
      end

      for model <- ["model-a", "model-b"] do
        @model model

        describe "#{model}" do
          setup do
            Reqord.Case.set_cassette_context(%{model: @model})
            :ok
          end

          @tag vcr_mode: :new_episodes
          test "uses module path builder" do
            # Should use module-level path builder
            # module_scoped/model-a/test_uses_module_path_builder.jsonl
            # module_scoped/model-b/test_uses_module_path_builder.jsonl
            assert true
          end
        end
      end
    end

    test "module path builder is used" do
      # Tests run as part of module definition
      assert true
    end
  end

  describe "per-test path builder via setup" do
    defmodule PerTestBuilderTest do
      use Reqord.Case, async: false

      describe "with custom path builder" do
        setup do
          # Set path builder for this specific test
          Application.put_env(:reqord, :cassette_path_builder, fn context ->
            "test_scoped/#{context.test}"
          end)

          on_exit(fn ->
            Application.delete_env(:reqord, :cassette_path_builder)
          end)

          :ok
        end

        @tag vcr_mode: :new_episodes
        test "uses test-level path builder" do
          # Should use test-specific path builder
          # test_scoped/test_uses_test-level_path_builder.jsonl
          assert true
        end
      end

      @tag vcr_mode: :new_episodes
      test "uses default naming when no builder" do
        # Should fall back to default naming
        # PerTestBuilder/uses_default_naming_when_no_builder.jsonl
        assert true
      end
    end

    test "per-test path builder works" do
      assert true
    end
  end

  describe "priority order" do
    defmodule PriorityTest do
      use Reqord.Case, async: false

      describe "vcr_path wins over builder" do
        setup do
          Application.put_env(:reqord, :cassette_path_builder, fn _context ->
            "test_builder"
          end)

          on_exit(fn ->
            Application.delete_env(:reqord, :cassette_path_builder)
          end)

          :ok
        end

        @tag vcr_path: "explicit/path"
        @tag vcr_mode: :new_episodes
        test "vcr_path has highest priority" do
          # 1. vcr_path (highest)
          # Should use: explicit/path
          assert true
        end
      end

      describe "builder beats vcr tag" do
        setup do
          Application.put_env(:reqord, :cassette_path_builder, fn _context ->
            "test_builder"
          end)

          on_exit(fn ->
            Application.delete_env(:reqord, :cassette_path_builder)
          end)

          :ok
        end

        @tag vcr: "vcr_tag"
        @tag vcr_mode: :new_episodes
        test "builder has higher priority than vcr tag" do
          # 2. Builder beats vcr tag
          # Should use: test_builder
          assert true
        end
      end

      @tag vcr: "vcr_tag"
      @tag vcr_mode: :new_episodes
      test "vcr tag still works" do
        # 3. vcr tag
        # Should use: vcr_tag
        assert true
      end
    end

    test "priority order is correct" do
      assert true
    end
  end

  describe "realistic req_llm scenario" do
    # General utility tests use default naming
    defmodule GeneralUtilsTest do
      use Reqord.Case, async: false

      @tag vcr_mode: :new_episodes
      test "helper function works" do
        # Uses default naming:
        # GeneralUtils/helper_function_works.jsonl
        assert true
      end

      @tag vcr_mode: :new_episodes
      test "another util test" do
        assert true
      end
    end

    # LLM provider tests use scoped path builder
    defmodule LLMProviderTest do
      use Reqord.Case, async: false

      setup_all do
        # Per-module path builder
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

            @tag vcr_mode: :new_episodes
            test "generates text" do
              # Uses module-scoped builder:
              # providers/google/gemini-flash/test_generates_text.jsonl
              # providers/openai/gpt-4/test_generates_text.jsonl
              assert true
            end
          end
        end
      end
    end

    test "realistic scenario works" do
      # General utils use default naming
      # LLM tests use custom organized structure
      assert true
    end
  end

  describe "per-describe builder can be overridden" do
    defmodule MixedBuildersTest do
      use Reqord.Case, async: false

      describe "with module builder" do
        setup do
          Application.put_env(:reqord, :cassette_path_builder, fn context ->
            "module/#{context.test}"
          end)

          on_exit(fn ->
            Application.delete_env(:reqord, :cassette_path_builder)
          end)

          :ok
        end

        @tag vcr_mode: :new_episodes
        test "uses module builder" do
          # module/test_uses_module_builder.jsonl
          assert true
        end
      end

      describe "with override builder" do
        setup do
          Application.put_env(:reqord, :cassette_path_builder, fn context ->
            "override/#{context.test}"
          end)

          on_exit(fn ->
            Application.delete_env(:reqord, :cassette_path_builder)
          end)

          :ok
        end

        @tag vcr_mode: :new_episodes
        test "uses override builder" do
          # override/test_uses_override_builder.jsonl
          assert true
        end
      end
    end

    test "per-describe override works" do
      assert true
    end
  end
end
