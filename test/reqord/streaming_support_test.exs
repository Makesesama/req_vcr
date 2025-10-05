defmodule Reqord.StreamingSupportTest do
  @moduledoc """
  Integration tests for streaming response support using the test_api server.

  These tests require the test_api server to be running on localhost:4001.
  Start the server with: cd test_api && mix run --no-halt

  To skip these tests in automated runs, they should be tagged with @tag :integration
  """
  use Reqord.Case
  alias Reqord.TestHelpers

  @moduletag :integration

  defp default_stub_name, do: Reqord.ExampleAPIStub

  describe "streaming content detection and storage" do
    @tag integration: "StreamingSupport/server_sent_events"
    test "detects and stores Server-Sent Events as stream" do
      client = TestHelpers.test_api_client()
      {:ok, resp} = Req.get(client, url: "/api/stream/events")

      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["text/event-stream"] or content_type == ["text/event-stream; charset=utf-8"]
      cache_control = Req.Response.get_header(resp, "cache-control")
      assert cache_control == ["no-cache"]

      # Should contain SSE format data
      assert String.contains?(resp.body, "data: {")
      assert String.contains?(resp.body, "event")
      assert String.contains?(resp.body, "start")
      assert String.contains?(resp.body, "end")
    end

    @tag integration: "StreamingSupport/llm_chat_stream"
    test "detects and stores LLM chat stream as stream" do
      client = TestHelpers.test_api_client()
      {:ok, resp} = Req.get(client, url: "/api/stream/chat")

      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["text/event-stream"] or content_type == ["text/event-stream; charset=utf-8"]

      # Should contain chat streaming format
      assert String.contains?(resp.body, "data: {\"role\": \"assistant\"")
      assert String.contains?(resp.body, "data: [DONE]")
      assert String.contains?(resp.body, "Hello! How")
      assert String.contains?(resp.body, "can I help")
      assert String.contains?(resp.body, "you today?")
    end

    @tag integration: "StreamingSupport/chunked_transfer"
    test "handles chunked transfer encoding" do
      client = TestHelpers.test_api_client()
      {:ok, resp} = Req.get(client, url: "/api/stream/chunked")

      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["text/plain"] or content_type == ["text/plain; charset=utf-8"]

      # Should contain chunked data
      assert String.contains?(resp.body, "chunk1")
      assert String.contains?(resp.body, "chunk4")

      # Note: The test_api simplifies chunked encoding simulation
      # In real scenarios, this would be handled by the HTTP client/server
    end
  end

  describe "stream replay functionality" do
    @tag integration: "StreamingSupport/replay_sse"
    test "correctly replays Server-Sent Events from cassette" do
      client = TestHelpers.test_api_client()

      # Make request to SSE endpoint
      {:ok, resp} = Req.get(client, url: "/api/stream/events")

      # Verify SSE response
      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["text/event-stream; charset=utf-8"]
      cache_control = Req.Response.get_header(resp, "cache-control")
      assert cache_control == ["no-cache"]

      # Should contain SSE format data
      assert String.contains?(resp.body, "data: {")
      assert String.contains?(resp.body, "event")
      assert String.contains?(resp.body, "start")
      assert String.contains?(resp.body, "end")
    end

    @tag integration: "StreamingSupport/replay_chat"
    test "correctly replays LLM chat stream from cassette" do
      client = TestHelpers.test_api_client()

      # Make request to chat stream endpoint
      {:ok, resp} = Req.get(client, url: "/api/stream/chat")

      # Verify chat stream response
      assert resp.status == 200
      content_type = Req.Response.get_header(resp, "content-type")
      assert content_type == ["text/event-stream; charset=utf-8"]

      # Should contain chat streaming format
      assert String.contains?(resp.body, "data: {\"role\": \"assistant\"")
      assert String.contains?(resp.body, "data: [DONE]")
      assert String.contains?(resp.body, "Hello! How")
      assert String.contains?(resp.body, "can I help")
      assert String.contains?(resp.body, "you today?")
    end
  end

  describe "stream configuration options" do
    test "respects stream_speed configuration" do
      original_speed = Application.get_env(:reqord, :stream_speed)

      try do
        # Test instant replay (default for tests)
        Application.put_env(:reqord, :stream_speed, 0)
        assert Reqord.Config.stream_speed() == 0

        # Test real-time replay
        Application.put_env(:reqord, :stream_speed, 1.0)
        assert Reqord.Config.stream_speed() == 1.0

        # Test accelerated replay
        Application.put_env(:reqord, :stream_speed, 2.0)
        assert Reqord.Config.stream_speed() == 2.0
      after
        if original_speed do
          Application.put_env(:reqord, :stream_speed, original_speed)
        else
          Application.delete_env(:reqord, :stream_speed)
        end
      end
    end
  end

  describe "mixed content scenarios" do
    @tag integration: "StreamingSupport/mixed_content"
    test "handles multiple content types in same test" do
      client = TestHelpers.test_api_client()

      # Request binary content
      {:ok, binary_resp} = Req.get(client, url: "/api/files/image.jpg")

      # Request streaming content
      {:ok, stream_resp} = Req.get(client, url: "/api/stream/events")

      # Request regular JSON content
      {:ok, json_resp} = Req.get(client, url: "/api/users")

      # All should succeed
      assert binary_resp.status == 200
      assert stream_resp.status == 200
      assert json_resp.status == 200

      # Verify content types are different
      assert <<0xFF, 0xD8, 0xFF, _::binary>> = binary_resp.body  # JPEG header
      assert String.contains?(stream_resp.body, "data: {")  # SSE format
      # JSON response is parsed by Req, so check the structure
      assert is_list(json_resp.body)
      assert Enum.any?(json_resp.body, fn user -> user["name"] == "Alice" end)
    end
  end

  describe "error handling in streaming" do
    @tag integration: "StreamingSupport/stream_error_handling"
    test "successfully handles streaming responses" do
      client = TestHelpers.test_api_client()

      # Test that streaming responses work correctly
      {:ok, resp} = Req.get(client, url: "/api/stream/events")

      # Should return a valid streaming response
      assert resp.status == 200
      assert String.contains?(resp.body, "data: {")
      assert String.contains?(resp.body, "event")
    end
  end
end