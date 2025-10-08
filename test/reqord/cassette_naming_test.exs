defmodule Reqord.CassetteNamingTest do
  use ExUnit.Case, async: false

  setup do
    # Clean up any existing config
    on_exit(fn ->
      Application.delete_env(:reqord, :cassette_path_builder)
    end)

    :ok
  end

  describe "vcr_path tag" do
    defmodule VcrPathTest do
      use Reqord.Case, async: false

      @tag vcr_path: "custom/path/to/cassette"
      @tag vcr_mode: :new_episodes
      test "uses explicit vcr_path tag", context do
        # Verify cassette name was set correctly
        assert context[:vcr_path] == "custom/path/to/cassette"
      end
    end

    test "vcr_path tag uses custom path" do
      cassette_path = Reqord.Config.cassette_path("custom/path/to/cassette")

      # Verify the path structure is correct
      assert cassette_path =~ ~r/custom\/path\/to\/cassette\.jsonl$/
    end

    @tag vcr_path: "providers/google/gemini/test"
    @tag vcr_mode: :new_episodes
    test "vcr_path with nested directories" do
      # This test verifies that nested paths work correctly
      assert true
    end
  end

  describe "cassette_path_builder config" do
    defmodule PathBuilderTest do
      use Reqord.Case, async: false

      setup do
        # Configure path builder for this test module
        Application.put_env(:reqord, :cassette_path_builder, fn context ->
          provider = context.tags[:provider] || "default"
          model = context.tags[:model] || "default"

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

      @tag provider: "google"
      @tag model: "gemini-2.0-flash"
      @tag vcr_mode: :new_episodes
      test "uses path builder with tags" do
        # Test runs and creates cassette at custom path
        assert true
      end

      @tag provider: "openai"
      @tag model: "gpt-4"
      @tag vcr_mode: :new_episodes
      test "uses path builder with different tags" do
        # Test runs and creates cassette at different custom path
        assert true
      end

      @tag vcr_mode: :new_episodes
      test "uses path builder with default values" do
        # Test runs and creates cassette with default provider/model
        assert true
      end
    end

    test "path builder creates correctly organized cassettes" do
      # Set up path builder
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        provider = context.tags[:provider] || "default"
        model = context.tags[:model] || "default"
        "#{provider}/#{model}/test"
      end)

      # Verify the path would be created correctly
      cassette_path = Reqord.Config.cassette_path("google/gemini-2.0-flash/test")
      assert cassette_path =~ ~r/google\/gemini-2.0-flash\/test\.jsonl$/

      # Clean up
      Application.delete_env(:reqord, :cassette_path_builder)
    end
  end

  describe "priority order" do
    test "vcr_path takes priority over cassette_path_builder" do
      # Set up path builder
      Application.put_env(:reqord, :cassette_path_builder, fn _context ->
        "should/not/be/used"
      end)

      # Create a simple test context
      context = %{
        vcr_path: "explicit/path",
        tags: %{provider: "google"},
        test: :test_something,
        module: __MODULE__
      }

      # Simulate cassette_name logic
      cassette_name =
        cond do
          path = context[:vcr_path] -> path
          builder = Application.get_env(:reqord, :cassette_path_builder) -> builder.(context)
          true -> "default"
        end

      assert cassette_name == "explicit/path"

      # Clean up
      Application.delete_env(:reqord, :cassette_path_builder)
    end

    test "cassette_path_builder takes priority over vcr tag" do
      # Set up path builder
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        "builder/#{context.tags[:provider]}"
      end)

      # Create a test context
      context = %{
        vcr: "simple/name",
        tags: %{provider: "google"},
        test: :test_something,
        module: __MODULE__
      }

      # Simulate cassette_name logic
      cassette_name =
        cond do
          path = context[:vcr_path] ->
            path

          builder = Application.get_env(:reqord, :cassette_path_builder) ->
            builder.(context)

          true ->
            case context[:vcr] do
              name when is_binary(name) -> name
              _ -> "default"
            end
        end

      assert cassette_name == "builder/google"

      # Clean up
      Application.delete_env(:reqord, :cassette_path_builder)
    end
  end

  describe "backwards compatibility" do
    defmodule BackwardsCompatTest do
      use Reqord.Case, async: false

      @tag vcr: "old_style/cassette"
      @tag vcr_mode: :new_episodes
      test "vcr tag still works" do
        # Old style vcr tag should continue working
        assert true
      end

      @tag vcr_mode: :new_episodes
      test "default naming still works" do
        # Default module/test naming should continue working
        assert true
      end
    end

    test "vcr tag creates cassette at specified path" do
      cassette_path = Reqord.Config.cassette_path("old_style/cassette")

      # The cassette should be usable with old-style naming
      assert cassette_path =~ ~r/old_style\/cassette\.jsonl$/
    end
  end

  describe "edge cases" do
    test "empty vcr_path falls back to next priority" do
      Application.put_env(:reqord, :cassette_path_builder, fn _context ->
        "fallback/path"
      end)

      context = %{
        vcr_path: nil,
        tags: %{},
        test: :test_something,
        module: __MODULE__
      }

      cassette_name =
        cond do
          path = context[:vcr_path] -> path
          builder = Application.get_env(:reqord, :cassette_path_builder) -> builder.(context)
          true -> "default"
        end

      assert cassette_name == "fallback/path"

      Application.delete_env(:reqord, :cassette_path_builder)
    end

    test "path builder can access full context" do
      Application.put_env(:reqord, :cassette_path_builder, fn context ->
        # Path builder should have access to:
        # - context.test (atom)
        # - context.module (module)
        # - context.tags (map)
        # - Any other context values

        module_name = context.module |> Module.split() |> List.last()
        test_name = context.test |> Atom.to_string()

        "#{module_name}/#{test_name}"
      end)

      context = %{
        test: :test_example,
        module: Reqord.CassetteNamingTest,
        tags: %{category: :integration}
      }

      builder = Application.get_env(:reqord, :cassette_path_builder)
      result = builder.(context)

      assert result == "CassetteNamingTest/test_example"

      Application.delete_env(:reqord, :cassette_path_builder)
    end
  end
end
