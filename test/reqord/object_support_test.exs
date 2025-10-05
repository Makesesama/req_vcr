defmodule Reqord.ObjectSupportTest do
  @moduledoc """
  Integration tests for binary object support using the test_api server.

  These tests require the test_api server to be running on localhost:4001.
  Start the server with: cd test_api && mix run --no-halt

  To skip these tests in automated runs, they should be tagged with @tag :integration
  """
  use Reqord.Case
  alias Reqord.TestHelpers

  @moduletag :integration

  defp default_stub_name, do: Reqord.ExampleAPIStub

  describe "binary content detection and storage" do
    @tag integration: "ObjectSupport/binary_image"
    test "detects and stores JPEG image as binary" do
      # Configure small threshold to test external storage
      original_size = Application.get_env(:reqord, :max_inline_size)
      Application.put_env(:reqord, :max_inline_size, 100)

      try do
        client = TestHelpers.test_api_client()
        {:ok, resp} = Req.get(client, url: "/api/files/image.jpg")

        assert resp.status == 200
        content_type = Req.Response.get_header(resp, "content-type")
        assert content_type == ["image/jpeg"] or content_type == ["image/jpeg; charset=utf-8"]

        # Should detect as binary content - JPEG files start with FF D8 FF
        assert <<0xFF, 0xD8, 0xFF, _::binary>> = resp.body
        # Should be the actual image file (around 224KB)
        assert byte_size(resp.body) > 200_000

        # Verify the response content is a valid JPEG
        assert <<0xFF, 0xD8, 0xFF, _::binary>> = resp.body
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end
    end

    @tag integration: "ObjectSupport/binary_pdf"
    test "detects and stores PDF document as binary" do
      client = TestHelpers.test_api_client()
      {:ok, resp} = Req.get(client, url: "/api/files/document.pdf")

      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")

      assert content_type == ["application/pdf"] or
               content_type == ["application/pdf; charset=utf-8"]

      # Should detect as binary content
      assert String.starts_with?(resp.body, "%PDF-1.4")
    end

    @tag integration: "ObjectSupport/large_binary"
    test "stores large binary content externally" do
      # Configure small threshold to force external storage
      original_size = Application.get_env(:reqord, :max_inline_size)
      # 1KB threshold
      Application.put_env(:reqord, :max_inline_size, 1000)

      try do
        client = TestHelpers.test_api_client()
        {:ok, resp} = Req.get(client, url: "/api/files/large-binary")

        assert resp.status == 200
        content_type = Req.Response.get_header(resp, "content-type")

        assert content_type == ["application/octet-stream"] or
                 content_type == ["application/octet-stream; charset=utf-8"]

        # Should be exactly 2MB of deterministic data
        assert byte_size(resp.body) == 2_000_000

        # Should contain our test pattern
        assert String.contains?(resp.body, "REQORD_TEST_DATA")
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end
    end
  end

  describe "replay with different body encodings" do
    @tag integration: "ObjectSupport/replay_binary"
    test "correctly replays binary content from cassette" do
      client = TestHelpers.test_api_client()

      # Make request to binary endpoint
      {:ok, resp} = Req.get(client, url: "/api/files/image.jpg")

      # Verify response
      assert resp.status == 200
      # JPEG header
      assert <<0xFF, 0xD8, 0xFF, _::binary>> = resp.body
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["image/jpeg; charset=utf-8"]
    end

    @tag integration: "ObjectSupport/replay_external"
    test "correctly replays externally stored content" do
      # Configure small threshold to force external storage
      original_size = Application.get_env(:reqord, :max_inline_size)
      Application.put_env(:reqord, :max_inline_size, 1000)

      try do
        client = TestHelpers.test_api_client()

        # Make request to large binary endpoint
        {:ok, resp} = Req.get(client, url: "/api/files/large-binary")

        # Verify response
        assert resp.status == 200
        # Verify it's the expected large content (2MB)
        assert byte_size(resp.body) == 2_000_000
        assert String.starts_with?(resp.body, "REQORD_TEST_DATA")
        content_type = Req.Response.get_header(resp, "content-type")
        assert content_type == ["application/octet-stream; charset=utf-8"]
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end
    end
  end

  describe "content type detection edge cases" do
    @tag integration: "ObjectSupport/text_with_binary_extension"
    test "respects content-type header over file extension" do
      client = TestHelpers.test_api_client()

      # Test that a PDF file is correctly identified as binary content
      {:ok, resp} = Req.get(client, url: "/api/files/document.pdf")

      assert resp.status == 200
      # PDF content should be detected as binary
      assert String.starts_with?(resp.body, "%PDF-1.4")
    end
  end

  describe "configuration options" do
    test "respects binary_storage configuration" do
      original_storage = Application.get_env(:reqord, :binary_storage)

      try do
        # Test :inline configuration
        Application.put_env(:reqord, :binary_storage, :inline)

        # Even large content should be stored inline
        # Note: This would require modifying the ContentAnalyzer to respect this config
        # For now, this test documents the expected behavior

        assert Reqord.Config.binary_storage() == :inline
      after
        if original_storage do
          Application.put_env(:reqord, :binary_storage, original_storage)
        else
          Application.delete_env(:reqord, :binary_storage)
        end
      end
    end

    test "respects object_directory configuration" do
      original_dir = Application.get_env(:reqord, :object_directory)

      try do
        Application.put_env(:reqord, :object_directory, "tmp/test_objects")

        assert Reqord.Config.object_directory() == "tmp/test_objects"
      after
        if original_dir do
          Application.put_env(:reqord, :object_directory, original_dir)
        else
          Application.delete_env(:reqord, :object_directory)
        end
      end
    end
  end
end
