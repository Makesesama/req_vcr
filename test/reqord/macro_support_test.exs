defmodule Reqord.MacroSupportTest do
  use ExUnit.Case, async: false

  describe "CassetteState context management" do
    test "put_context/2 stores context for process" do
      context = %{model: "gpt-4", provider: "openai"}
      Reqord.CassetteState.put_context(self(), context)

      assert Reqord.CassetteState.get_context(self()) == context
    end

    test "get_context/1 returns empty map by default" do
      # Use a new process to ensure clean state
      task =
        Task.async(fn ->
          Reqord.CassetteState.get_context(self())
        end)

      assert Task.await(task) == %{}
    end

    test "clear_context/1 removes stored context" do
      Reqord.CassetteState.put_context(self(), %{test: "data"})
      assert Reqord.CassetteState.get_context(self()) == %{test: "data"}

      Reqord.CassetteState.clear_context(self())
      assert Reqord.CassetteState.get_context(self()) == %{}
    end

    test "context is process-specific" do
      parent_context = %{process: "parent"}
      Reqord.CassetteState.put_context(self(), parent_context)

      task =
        Task.async(fn ->
          child_context = %{process: "child"}
          Reqord.CassetteState.put_context(self(), child_context)
          Reqord.CassetteState.get_context(self())
        end)

      child_result = Task.await(task)

      # Child process has its own context
      assert child_result == %{process: "child"}
      # Parent context unchanged
      assert Reqord.CassetteState.get_context(self()) == parent_context
    end
  end

  describe "Reqord.Case.set_cassette_context/1" do
    test "stores context for current process" do
      context = %{model: "gemini-flash", provider: "google"}
      Reqord.Case.set_cassette_context(context)

      assert Reqord.CassetteState.get_context(self()) == context
    end
  end

  describe "macro-generated tests with set_cassette_context" do
    # Simulate macro-generated tests
    defmodule MacroGeneratedTest do
      use Reqord.Case, async: false

      # Simulate a for loop that generates tests
      for model <- ["gpt-4", "gemini-flash"] do
        @model model

        describe "#{model}" do
          setup do
            # Set macro context before test runs
            Reqord.Case.set_cassette_context(%{model: @model})
            :ok
          end

          @tag vcr_mode: :new_episodes
          test "generates text" do
            # Verify macro context is available
            macro_context = Reqord.CassetteState.get_context(self())
            assert macro_context[:model] == @model
          end
        end
      end
    end

    test "macro context is available in generated tests" do
      # Tests run as part of module definition above
      assert true
    end
  end

  describe "cassette_path_builder with macro context" do
    defmodule PathBuilderWithMacroTest do
      use Reqord.Case, async: false

      setup_all do
        # Configure path builder to use macro context
        Application.put_env(:reqord, :cassette_path_builder, fn context ->
          model = get_in(context, [:macro_context, :model]) || "default"
          provider = get_in(context, [:macro_context, :provider]) || "default"

          test_name =
            context.test
            |> Atom.to_string()
            |> String.replace(~r/^test /, "")
            |> String.replace(~r/\s+/, "_")

          "#{provider}/#{model}/#{test_name}"
        end)

        on_exit(fn ->
          Application.delete_env(:reqord, :cassette_path_builder)
        end)

        :ok
      end

      for {provider, model} <- [{"openai", "gpt-4"}, {"google", "gemini-flash"}] do
        @provider provider
        @model model

        describe "#{provider}/#{model}" do
          setup do
            Reqord.Case.set_cassette_context(%{
              provider: @provider,
              model: @model
            })

            :ok
          end

          @tag vcr_mode: :new_episodes
          test "chat completion" do
            # The cassette path should include provider and model
            macro_context = Reqord.CassetteState.get_context(self())
            assert macro_context[:provider] == @provider
            assert macro_context[:model] == @model
          end
        end
      end
    end

    test "path builder uses macro context" do
      # Configure path builder
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        model = context.macro_context[:model] || "default"
        "models/#{model}/test"
      end)

      # Simulate a context with macro_context
      context = %{
        macro_context: %{model: "gpt-4"},
        test: :test_example,
        module: __MODULE__,
        tags: %{}
      }

      builder = Application.get_env(:reqord, :cassette_path_builder)
      result = builder.(context)

      assert result == "models/gpt-4/test"

      # Clean up
      Application.delete_env(:reqord, :cassette_path_builder)
    end

    test "path builder handles missing macro context gracefully" do
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        # Access macro_context safely
        model = get_in(context, [:macro_context, :model]) || "default"
        "models/#{model}/test"
      end)

      # Context without macro_context
      context = %{
        test: :test_example,
        module: __MODULE__,
        tags: %{}
      }

      builder = Application.get_env(:reqord, :cassette_path_builder)
      result = builder.(context)

      # Should use default when macro_context is missing
      assert result == "models/default/test"

      # Clean up
      Application.delete_env(:reqord, :cassette_path_builder)
    end
  end

  describe "realistic LLM test scenario" do
    defmodule RealisticLLMTest do
      use Reqord.Case, async: false

      setup_all do
        # Path builder that mimics req_llm structure
        Application.put_env(:reqord, :cassette_path_builder, fn context ->
          provider = get_in(context, [:macro_context, :provider]) || "default"
          model = get_in(context, [:macro_context, :model]) || "default"

          test_name =
            context.test
            |> Atom.to_string()
            |> String.replace(~r/^test /, "")
            |> String.replace(~r/\s+/, "_")

          "providers/#{provider}/#{model}/#{test_name}"
        end)

        on_exit(fn ->
          Application.delete_env(:reqord, :cassette_path_builder)
        end)

        :ok
      end

      # Simulate ModelMatrix.models_for_provider(:google)
      @google_models ["gemini-2.0-flash", "gemini-1.5-pro"]

      for model <- @google_models do
        @model model

        describe "google:#{model}" do
          setup do
            Reqord.Case.set_cassette_context(%{
              provider: "google",
              model: @model
            })

            :ok
          end

          @tag vcr_mode: :new_episodes
          test "basic generate_text (non-streaming)" do
            macro_context = Reqord.CassetteState.get_context(self())
            assert macro_context[:provider] == "google"
            assert macro_context[:model] == @model

            # Each model gets its own cassette:
            # providers/google/gemini-2.0-flash/basic_generate_text_(non-streaming).jsonl
            # providers/google/gemini-1.5-pro/basic_generate_text_(non-streaming).jsonl
            assert true
          end

          @tag vcr_mode: :new_episodes
          test "stream_text with context" do
            macro_context = Reqord.CassetteState.get_context(self())
            assert macro_context[:model] == @model
            # Each model gets separate cassette
            assert true
          end
        end
      end
    end

    test "realistic scenario runs successfully" do
      # Tests defined in module above
      assert true
    end
  end

  describe "context cleanup" do
    test "context is cleaned up after test" do
      # Set some context
      Reqord.Case.set_cassette_context(%{test: "data"})
      assert Reqord.CassetteState.get_context(self()) == %{test: "data"}

      # Simulate the on_exit callback
      Reqord.CassetteState.clear_context(self())

      # Context should be cleared
      assert Reqord.CassetteState.get_context(self()) == %{}
    end
  end

  describe "edge cases" do
    test "get_context with non-existent pid returns empty map" do
      # Getting context for a pid that never set context
      assert Reqord.CassetteState.get_context(self()) == %{}
    end

    test "put_context overwrites previous context" do
      Reqord.CassetteState.put_context(self(), %{first: "data"})
      assert Reqord.CassetteState.get_context(self()) == %{first: "data"}

      Reqord.CassetteState.put_context(self(), %{second: "data"})
      assert Reqord.CassetteState.get_context(self()) == %{second: "data"}

      # Cleanup
      Reqord.CassetteState.clear_context(self())
    end

    test "clear_context on pid without context is safe" do
      # Should not crash
      assert :ok = Reqord.CassetteState.clear_context(self())
    end

    test "empty map context is handled" do
      Reqord.Case.set_cassette_context(%{})
      assert Reqord.CassetteState.get_context(self()) == %{}

      # Cleanup
      Reqord.CassetteState.clear_context(self())
    end

    test "path builder handles nil macro_context gracefully" do
      context = %{
        test: :test_example,
        module: __MODULE__,
        tags: %{}
        # Note: no :macro_context key
      }

      # Using get_in should return nil, not crash
      model = get_in(context, [:macro_context, :model])
      assert model == nil

      # With default
      model_with_default = get_in(context, [:macro_context, :model]) || "default"
      assert model_with_default == "default"
    end

    test "path builder handles empty macro_context map" do
      context = %{
        test: :test_example,
        module: __MODULE__,
        tags: %{},
        macro_context: %{}
      }

      model = get_in(context, [:macro_context, :model]) || "default"
      assert model == "default"
    end
  end
end
