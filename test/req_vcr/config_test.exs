defmodule ReqVCR.ConfigTest do
  use ExUnit.Case
  import ReqVCR.TestHelpers

  describe "ReqVCR.Config" do
    test "provides default cassette directory" do
      assert ReqVCR.Config.cassette_dir() == "test/support/cassettes"
    end

    test "provides default auth parameters" do
      auth_params = ReqVCR.Config.auth_params()
      assert is_list(auth_params)
      assert "token" in auth_params
      assert "apikey" in auth_params
      assert "api_key" in auth_params
      assert "access_token" in auth_params
    end

    test "provides default auth headers" do
      auth_headers = ReqVCR.Config.auth_headers()
      assert is_list(auth_headers)
      assert "authorization" in auth_headers
      assert "x-api-key" in auth_headers
      assert "cookie" in auth_headers
    end

    test "provides default volatile headers" do
      volatile_headers = ReqVCR.Config.volatile_headers()
      assert is_list(volatile_headers)
      assert "date" in volatile_headers
      assert "server" in volatile_headers
      assert "set-cookie" in volatile_headers
      assert "request-id" in volatile_headers
    end

    test "cassette_path constructs correct path" do
      path = ReqVCR.Config.cassette_path("my_test")
      assert String.ends_with?(path, "test/support/cassettes/my_test.jsonl")
    end

    test "can override cassette directory via config" do
      with_config(:req_vcr, :cassette_dir, "custom/cassette/dir", fn ->
        assert ReqVCR.Config.cassette_dir() == "custom/cassette/dir"

        path = ReqVCR.Config.cassette_path("test")
        assert String.ends_with?(path, "custom/cassette/dir/test.jsonl")
      end)
    end

    test "can override auth parameters via config" do
      custom_params = ["my_token", "my_key"]

      with_config(:req_vcr, :auth_params, custom_params, fn ->
        assert ReqVCR.Config.auth_params() == custom_params
      end)
    end

    test "can override auth headers via config" do
      custom_headers = ["x-my-auth", "my-auth-header"]

      with_config(:req_vcr, :auth_headers, custom_headers, fn ->
        assert ReqVCR.Config.auth_headers() == custom_headers
      end)
    end

    test "can override volatile headers via config" do
      custom_volatile = ["x-timestamp", "x-request-uuid"]

      with_config(:req_vcr, :volatile_headers, custom_volatile, fn ->
        assert ReqVCR.Config.volatile_headers() == custom_volatile
      end)
    end

    test "validates configuration correctly" do
      assert ReqVCR.Config.validate() == :ok
    end

    test "validation detects invalid cassette directory" do
      with_config(:req_vcr, :cassette_dir, 123, fn ->
        {:error, errors} = ReqVCR.Config.validate()
        assert Enum.any?(errors, fn {key, _} -> key == :cassette_dir end)
      end)
    end

    test "validation detects invalid json library" do
      with_config(:req_vcr, :json_library, InvalidModule, fn ->
        {:error, errors} = ReqVCR.Config.validate()
        assert Enum.any?(errors, fn {key, _} -> key == :json_library end)
      end)
    end

    test "provides empty custom filters by default" do
      assert ReqVCR.Config.custom_filters() == []
    end

    test "can configure custom filters" do
      filters = [{"<TOKEN>", fn -> "secret123" end}]

      with_config(:req_vcr, :filters, filters, fn ->
        assert ReqVCR.Config.custom_filters() == filters
      end)
    end
  end
end
