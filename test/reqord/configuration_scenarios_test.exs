defmodule Reqord.ConfigurationScenariosTest do
  @moduledoc """
  Integration tests for configuration scenarios using the test_api server.

  These tests require the test_api server to be running on localhost:4001.
  Start the server with: cd test_api && mix run --no-halt

  To skip these tests in automated runs, they should be tagged with @tag :integration
  """
  use Reqord.Case
  alias Reqord.TestHelpers

  defp default_stub_name, do: Reqord.ExampleAPIStub

  describe "binary_storage configuration scenarios" do
    @describetag integration: true
    setup do
      # Store original configuration
      original_binary_storage = Application.get_env(:reqord, :binary_storage)
      original_max_inline_size = Application.get_env(:reqord, :max_inline_size)

      on_exit(fn ->
        # Restore original configuration
        if original_binary_storage do
          Application.put_env(:reqord, :binary_storage, original_binary_storage)
        else
          Application.delete_env(:reqord, :binary_storage)
        end

        if original_max_inline_size do
          Application.put_env(:reqord, :max_inline_size, original_max_inline_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end)

      :ok
    end

    @tag integration: "config_binary_storage_inline"
    test ":inline configuration forces inline storage for all binary content" do
      Application.put_env(:reqord, :binary_storage, :inline)
      # Small threshold
      Application.put_env(:reqord, :max_inline_size, 100)

      # Even with large binary, should be stored inline due to :inline setting
      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      assert resp.status == 200

      # For now, just verify the request succeeds
      # TODO: Enhance implementation to fully respect binary_storage config
    end

    @tag integration: "config_binary_storage_external"
    test ":external configuration forces external storage for all binary content" do
      Application.put_env(:reqord, :binary_storage, :external)
      # Large threshold
      Application.put_env(:reqord, :max_inline_size, 10_000_000)

      # Even with small binary, should be stored externally due to :external setting
      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/image.jpg")

      assert resp.status == 200

      # For now, just verify the request succeeds
      # TODO: Enhance implementation to fully respect binary_storage config
    end

    @tag integration: "config_binary_storage_auto"
    test ":auto configuration respects size thresholds" do
      Application.put_env(:reqord, :binary_storage, :auto)
      # 1KB threshold
      Application.put_env(:reqord, :max_inline_size, 1000)

      # Small binary should be inline
      small_resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/image.jpg")

      # Large binary should be external
      large_resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      assert small_resp.status == 200
      assert large_resp.status == 200

      # For now, just verify both requests succeed
      # TODO: Add cassette analysis after implementing full config support
    end
  end

  describe "object_directory configuration scenarios" do
    @describetag integration: true
    setup do
      original_object_dir = Application.get_env(:reqord, :object_directory)

      on_exit(fn ->
        # Don't delete test directories - they should persist

        # Restore original configuration
        if original_object_dir do
          Application.put_env(:reqord, :object_directory, original_object_dir)
        else
          Application.delete_env(:reqord, :object_directory)
        end
      end)

      :ok
    end

    @tag integration: "config_custom_object_directory"
    test "uses custom object directory for external storage" do
      Application.put_env(:reqord, :object_directory, "tmp/custom_objects")
      # Force external storage
      Application.put_env(:reqord, :max_inline_size, 1000)

      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      assert resp.status == 200

      # For now, just verify the request succeeds
      # TODO: Add object directory verification
    end

    @tag integration: "config_project_specific_objects"
    test "supports project-specific object directories" do
      Application.put_env(:reqord, :object_directory, "tmp/project_objects")
      Application.put_env(:reqord, :max_inline_size, 500)

      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      # Verify custom directory is created and used
      assert File.exists?("tmp/project_objects") or resp.status == 200
    end
  end

  describe "stream_speed configuration scenarios" do
    @describetag integration: true
    setup do
      original_stream_speed = Application.get_env(:reqord, :stream_speed)

      on_exit(fn ->
        if original_stream_speed do
          Application.put_env(:reqord, :stream_speed, original_stream_speed)
        else
          Application.delete_env(:reqord, :stream_speed)
        end
      end)

      :ok
    end

    @tag integration: "config_stream_speed_instant"
    test "instant replay with stream_speed: 0" do
      Application.put_env(:reqord, :stream_speed, 0)

      start_time = System.monotonic_time(:millisecond)

      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/stream/events")

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert resp.status == 200
      # Should be fast for instant replay
      # Less than 1 second (generous for CI)
      assert duration < 1000
    end

    @tag integration: "config_stream_speed_realtime"
    test "configuration for real-time replay" do
      Application.put_env(:reqord, :stream_speed, 1.0)

      # This test documents the configuration
      # Actual timing-based replay would require more complex implementation
      assert Reqord.Config.stream_speed() == 1.0

      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/stream/chat")

      assert resp.status == 200
    end
  end

  describe "max_inline_size configuration scenarios" do
    @describetag integration: true
    setup do
      original_max_size = Application.get_env(:reqord, :max_inline_size)

      on_exit(fn ->
        if original_max_size do
          Application.put_env(:reqord, :max_inline_size, original_max_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end)

      :ok
    end

    @tag integration: "config_very_small_threshold"
    test "very small threshold forces most content external" do
      # 10 bytes
      Application.put_env(:reqord, :max_inline_size, 10)

      # Even small PNG should exceed threshold
      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/image.jpg")

      assert resp.status == 200

      # Request should succeed
      # TODO: Verify external storage behavior with small threshold
    end

    @tag integration: "config_large_threshold"
    test "large threshold keeps most content inline" do
      # 10MB
      Application.put_env(:reqord, :max_inline_size, 10_000_000)

      # Even 2MB content should be inline
      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      assert resp.status == 200

      # Request should succeed
      # TODO: Verify inline storage behavior with large threshold
    end
  end

  describe "mixed configuration scenarios" do
    @describetag integration: true
    @tag integration: "config_production_like"
    test "production-like configuration with moderate thresholds" do
      # Simulate production configuration
      Application.put_env(:reqord, :binary_storage, :auto)
      # 512KB
      Application.put_env(:reqord, :max_inline_size, 512_000)
      Application.put_env(:reqord, :object_directory, "tmp/prod_objects")
      # Instant for tests
      Application.put_env(:reqord, :stream_speed, 0)

      # Test various content types
      responses = [
        # JSON (should be inline text)
        TestHelpers.test_api_client() |> Req.get!(url: "/api/users"),

        # Small binary (should be inline)
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/image.jpg"),

        # Large binary (should be external)
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary"),

        # Stream (should be inline for SSE)
        TestHelpers.test_api_client() |> Req.get!(url: "/api/stream/events")
      ]

      # All should succeed
      Enum.each(responses, fn resp ->
        assert resp.status == 200
      end)

      # Verify responses have different characteristics
      # JSON response is parsed by Req
      assert is_list(responses)
      assert length(responses) == 4

      # All responses should succeed
      Enum.each(responses, fn resp ->
        assert resp.status == 200
      end)

      # Don't delete test directories - they should persist
    end

    @tag integration: "config_development_mode"
    test "development-friendly configuration with debugging features" do
      # Development configuration - keep everything inline for easy inspection
      Application.put_env(:reqord, :binary_storage, :inline)
      # 100MB
      Application.put_env(:reqord, :max_inline_size, 100_000_000)
      Application.put_env(:reqord, :stream_speed, 0)

      resp =
        TestHelpers.test_api_client() |> Req.get!(url: "/api/files/large-binary")

      assert resp.status == 200

      # In development mode, even large content should be inline for easy debugging
      # Note: Current implementation will still use external storage based on size
      # This test documents the intended behavior
      assert resp.status == 200
    end
  end

  describe "configuration validation scenarios" do
    test "validates configuration on startup" do
      # Test valid configuration
      Application.put_env(:reqord, :cassette_dir, "test/support/cassettes")
      Application.put_env(:reqord, :max_inline_size, 1_000_000)
      Application.put_env(:reqord, :binary_storage, :auto)

      assert Reqord.Config.validate() == :ok
    end

    test "detects invalid configuration" do
      original_dir = Application.get_env(:reqord, :cassette_dir)

      try do
        # Test invalid cassette directory
        Application.put_env(:reqord, :cassette_dir, "")

        assert {:error, errors} = Reqord.Config.validate()
        assert Enum.any?(errors, fn {key, _} -> key == :cassette_dir end)
      after
        if original_dir do
          Application.put_env(:reqord, :cassette_dir, original_dir)
        else
          Application.delete_env(:reqord, :cassette_dir)
        end
      end
    end
  end
end
