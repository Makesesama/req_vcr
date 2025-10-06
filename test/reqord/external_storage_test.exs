defmodule Reqord.ExternalStorageTest do
  use ExUnit.Case
  alias Reqord.CassetteEntry
  alias Reqord.Storage.FileSystem

  @test_object_dir "tmp/test_objects"

  setup do
    original_object_dir = Application.get_env(:reqord, :object_directory)
    Application.put_env(:reqord, :object_directory, @test_object_dir)

    on_exit(fn ->
      if original_object_dir do
        Application.put_env(:reqord, :object_directory, original_object_dir)
      else
        Application.delete_env(:reqord, :object_directory)
      end
    end)

    :ok
  end

  describe "FileSystem storage backend - objects" do
    test "stores and retrieves binary objects" do
      content = :crypto.strong_rand_bytes(1024)
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      assert {:ok, ^content_hash} = FileSystem.store_object(content_hash, content)

      expected_path =
        Path.join([@test_object_dir, String.slice(content_hash, 0, 2), content_hash])

      assert File.exists?(expected_path)
      assert {:ok, ^content} = FileSystem.load_object(content_hash)
    end

    test "handles duplicate object storage" do
      content = "test content"
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      assert {:ok, ^content_hash} = FileSystem.store_object(content_hash, content)
      assert {:ok, ^content_hash} = FileSystem.store_object(content_hash, content)
      assert {:ok, ^content} = FileSystem.load_object(content_hash)
    end

    test "returns error for non-existent objects" do
      non_existent_hash = "nonexistent123456789"
      assert {:error, :not_found} = FileSystem.load_object(non_existent_hash)
    end

    test "handles large binary objects" do
      large_content = :crypto.strong_rand_bytes(5_000_000)
      content_hash = :crypto.hash(:sha256, large_content) |> Base.encode16(case: :lower)

      assert {:ok, ^content_hash} = FileSystem.store_object(content_hash, large_content)
      assert {:ok, ^large_content} = FileSystem.load_object(content_hash)
    end

    test "handles directory creation for nested paths" do
      content = "test"
      custom_hash = "ff1234567890abcdef"

      assert {:ok, ^custom_hash} = FileSystem.store_object(custom_hash, content)

      expected_dir = Path.join(@test_object_dir, "ff")
      assert File.exists?(expected_dir)

      expected_path = Path.join(expected_dir, custom_hash)
      assert File.exists?(expected_path)
    end
  end

  describe "FileSystem storage backend - streams" do
    test "stores and retrieves stream chunks" do
      chunks = [
        %{"timestamp" => 1000, "data" => "chunk1"},
        %{"timestamp" => 2000, "data" => "chunk2"},
        %{"timestamp" => 3000, "data" => "chunk3"}
      ]

      stream_hash = "stream123"

      assert {:ok, ^stream_hash} = FileSystem.store_stream(stream_hash, chunks)

      expected_path = Path.join([@test_object_dir, "streams", "#{stream_hash}.json"])
      assert File.exists?(expected_path)
      assert {:ok, ^chunks} = FileSystem.load_stream(stream_hash)
    end

    test "handles empty stream chunks" do
      empty_chunks = []
      stream_hash = "empty_stream"

      assert {:ok, ^stream_hash} = FileSystem.store_stream(stream_hash, empty_chunks)
      assert {:ok, ^empty_chunks} = FileSystem.load_stream(stream_hash)
    end

    test "returns error for non-existent streams" do
      assert {:error, :not_found} = FileSystem.load_stream("nonexistent_stream")
    end

    test "handles large stream data" do
      chunks =
        for i <- 1..1000 do
          %{"timestamp" => i * 100, "data" => "chunk #{i} with some data"}
        end

      stream_hash = "large_stream"

      assert {:ok, ^stream_hash} = FileSystem.store_stream(stream_hash, chunks)
      assert {:ok, ^chunks} = FileSystem.load_stream(stream_hash)
    end
  end

  describe "automatic external storage decision" do
    test "ContentAnalyzer.should_store_externally? respects configuration" do
      original_size = Application.get_env(:reqord, :max_inline_size)

      try do
        Application.put_env(:reqord, :max_inline_size, 100)

        assert Reqord.ContentAnalyzer.should_store_externally?(:binary, 50) == false
        assert Reqord.ContentAnalyzer.should_store_externally?(:binary, 200) == true
        assert Reqord.ContentAnalyzer.should_store_externally?(:stream, 200) == true
        assert Reqord.ContentAnalyzer.should_store_externally?(:text, 200) == false
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end
    end
  end

  describe "integration with CassetteEntry.Response" do
    test "creates response with external storage for large binary" do
      large_content = :crypto.strong_rand_bytes(2_000_000)
      headers = %{"content-type" => "application/octet-stream"}

      original_size = Application.get_env(:reqord, :max_inline_size)
      Application.put_env(:reqord, :max_inline_size, 1000)

      try do
        {:ok, response} = CassetteEntry.Response.new_with_raw_body(200, headers, large_content)

        assert response.body_encoding == "external_binary"
        assert response.body_b64 == ""
        assert is_binary(response.body_external_ref)
        assert is_map(response.stream_metadata)
        assert response.stream_metadata["size"] == byte_size(large_content)

        {:ok, stored_content} = FileSystem.load_object(response.body_external_ref)
        assert stored_content == large_content
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end
      end
    end

    test "creates response with inline storage for small binary" do
      small_content = :crypto.strong_rand_bytes(100)
      headers = %{"content-type" => "image/png"}

      {:ok, response} = CassetteEntry.Response.new_with_raw_body(200, headers, small_content)

      assert response.body_encoding == "binary"
      assert Base.decode64!(response.body_b64) == small_content
      assert response.body_external_ref == nil
    end

    test "creates response with stream metadata for SSE content" do
      sse_content = """
      data: {"message": "hello"}

      data: {"message": "world"}

      """

      headers = %{"content-type" => "text/event-stream"}

      {:ok, response} = CassetteEntry.Response.new_with_raw_body(200, headers, sse_content)

      assert response.body_encoding == "stream"
      assert Base.decode64!(response.body_b64) == sse_content
      assert is_map(response.stream_metadata)
      assert response.stream_metadata["type"] == "stream"
      assert response.stream_metadata["size"] == byte_size(sse_content)
    end

    test "falls back to inline storage when external storage fails" do
      content = "test content"
      headers = %{"content-type" => "application/octet-stream"}

      original_size = Application.get_env(:reqord, :max_inline_size)
      Application.put_env(:reqord, :max_inline_size, 1)

      original_dir = Application.get_env(:reqord, :object_directory)
      Application.put_env(:reqord, :object_directory, "/nonexistent/readonly")

      try do
        {:ok, response} = CassetteEntry.Response.new_with_raw_body(200, headers, content)

        assert response.body_encoding == "binary"
        assert Base.decode64!(response.body_b64) == content
        assert response.body_external_ref == nil
      after
        if original_size do
          Application.put_env(:reqord, :max_inline_size, original_size)
        else
          Application.delete_env(:reqord, :max_inline_size)
        end

        if original_dir do
          Application.put_env(:reqord, :object_directory, original_dir)
        else
          Application.delete_env(:reqord, :object_directory)
        end
      end
    end
  end

  describe "cleanup and maintenance" do
    test "objects persist for future use" do
      content = "test content"
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      {:ok, _} = FileSystem.store_object(content_hash, content)
      assert {:ok, ^content} = FileSystem.load_object(content_hash)
    end

    test "stream files persist for future use" do
      chunks = [%{"data" => "test"}]
      stream_hash = "test_stream"

      {:ok, _} = FileSystem.store_stream(stream_hash, chunks)
      assert {:ok, ^chunks} = FileSystem.load_stream(stream_hash)
    end
  end
end
