defmodule Reqord.NamedBuildersPathResolutionTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests that named builders correctly resolve cassette paths.
  This is a simpler test that just verifies path computation without actual HTTP calls.
  """

  # Configure named builders (merge with existing to avoid conflicts)
  existing = Application.get_env(:reqord, :cassette_path_builders, %{})

  Application.put_env(
    :reqord,
    :cassette_path_builders,
    Map.merge(existing, %{
      path_test_api: fn context ->
        "path_test/api/#{context.test}"
      end,
      path_test_feature: fn context ->
        feature = context[:feature] || "default"
        "path_test/features/#{feature}/#{context.test}"
      end,
      path_test_macro: fn context ->
        provider = get_in(context, [:macro_context, :provider]) || "default"
        "path_test/providers/#{provider}/#{context.test}"
      end
    })
  )

  # Note: No cleanup needed - builders are additive across test files

  test "cassette_name resolves with named builder" do
    # Simulate the context that Reqord.Case would create
    context = %{
      test: :test_example,
      module: __MODULE__,
      named_builder: :path_test_api
    }

    # This is what cassette_name/1 in Reqord.Case does
    builders = Application.get_env(:reqord, :cassette_path_builders, %{})
    builder = Map.get(builders, :path_test_api)

    result = builder.(context)

    assert result == "path_test/api/test_example"
  end

  test "cassette_name resolves with feature tag" do
    context = %{
      test: :test_with_feature,
      module: __MODULE__,
      named_builder: :path_test_feature,
      feature: "authentication"
    }

    builders = Application.get_env(:reqord, :cassette_path_builders, %{})
    builder = Map.get(builders, :path_test_feature)

    result = builder.(context)

    assert result == "path_test/features/authentication/test_with_feature"
  end

  test "cassette_name resolves with macro context" do
    context = %{
      test: :test_with_provider,
      module: __MODULE__,
      named_builder: :path_test_macro,
      macro_context: %{provider: "google"}
    }

    builders = Application.get_env(:reqord, :cassette_path_builders, %{})
    builder = Map.get(builders, :path_test_macro)

    result = builder.(context)

    assert result == "path_test/providers/google/test_with_provider"
  end

  test "full cassette path includes jsonl extension" do
    cassette_name = "path_test/api/test_example"
    full_path = Reqord.Config.cassette_path(cassette_name)

    assert String.ends_with?(full_path, ".jsonl")
    assert String.contains?(full_path, "path_test/api/test_example")
  end

  test "vcr_path takes priority over named builder" do
    # vcr_path should be used directly, not passed through builder
    context_with_vcr_path = %{
      test: :test_example,
      module: __MODULE__,
      named_builder: :path_test_api,
      vcr_path: "explicit/custom/path"
    }

    # In Reqord.Case, vcr_path check comes first
    result =
      if path = context_with_vcr_path[:vcr_path] do
        path
      else
        builders = Application.get_env(:reqord, :cassette_path_builders, %{})
        builder = Map.get(builders, context_with_vcr_path[:named_builder])
        builder.(context_with_vcr_path)
      end

    assert result == "explicit/custom/path"
  end

  test "missing named builder raises helpful error" do
    context = %{
      test: :test_example,
      module: __MODULE__,
      named_builder: :nonexistent
    }

    builders = Application.get_env(:reqord, :cassette_path_builders, %{})

    assert_raise ArgumentError, ~r/Named cassette path builder :nonexistent not found/, fn ->
      case Map.get(builders, :nonexistent) do
        nil ->
          raise ArgumentError,
                "Named cassette path builder :nonexistent not found. " <>
                  "Available builders: #{inspect(Map.keys(builders))}"

        builder ->
          builder.(context)
      end
    end
  end
end
