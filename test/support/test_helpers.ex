defmodule Reqord.TestHelpers do
  @moduledoc """
  Shared test utilities for Reqord tests.
  """

  @doc """
  Runs a test function only if the given module is available.

  If the module is not available, logs a skip message and returns `:ok`.
  If the module is available, executes the provided function.

  ## Examples

      test "my poison test" do
        with_module(Poison, "Poison", fn ->
          # test code here
          assert Poison.encode!(%{test: true}) == ~s({"test":true})
        end)
      end
  """
  def with_module(module, module_name, test_function)
      when is_atom(module) and is_binary(module_name) and is_function(test_function, 0) do
    if Code.ensure_loaded?(module) do
      test_function.()
    else
      IO.puts("Skipping #{module_name} tests - #{module_name} not available")
      :ok
    end
  end

  @doc """
  Runs a test function with application configuration setup and teardown.

  Sets the specified application configuration before running the test,
  then restores the original configuration afterward.

  ## Examples

      test "with custom config" do
        with_config(:reqord, :json_library, MyAdapter, fn ->
          # test code with MyAdapter configured
          assert Reqord.JSON.encode!(%{}) == "{}"
        end)
      end
  """
  def with_config(app, key, value, test_function)
      when is_atom(app) and is_function(test_function, 0) do
    original_value = Application.get_env(app, key)

    try do
      Application.put_env(app, key, value)
      test_function.()
    after
      if original_value do
        Application.put_env(app, key, original_value)
      else
        Application.delete_env(app, key)
      end
    end
  end

  @doc """
  Combines module availability check with configuration setup.

  Only runs the test if the module is available, and handles configuration
  setup/teardown automatically.

  ## Examples

      test "poison with config" do
        with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
          # test code here
          assert Reqord.JSON.encode!(%{test: true}) |> String.contains?("test")
        end)
      end
  """
  def with_module_and_config(module, module_name, app, key, value, test_function)
      when is_atom(module) and is_binary(module_name) and is_atom(app) and
             is_function(test_function, 0) do
    with_module(module, module_name, fn ->
      with_config(app, key, value, test_function)
    end)
  end

  @doc """
  Test API client fixture for integration tests.

  Returns a Req client pre-configured with authentication headers and base URL
  for the test_api server.

  ## Examples

      test "get user" do
        client = TestHelpers.test_api_client()
        {:ok, resp} = Req.get(client, url: "/api/users/1")
        assert resp.status == 200
      end

      test "create user" do
        client = TestHelpers.test_api_client()
        {:ok, resp} = Req.post(client, url: "/api/users", json: %{name: "Alice"})
        assert resp.status == 201
      end
  """
  def test_api_client do
    Req.new(
      plug: {Req.Test, Reqord.ExampleAPIStub},
      base_url: "http://localhost:4001",
      headers: [{"authorization", "Bearer test-token"}]
    )
  end
end
