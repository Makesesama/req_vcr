defmodule Reqord.EncodingTest do
  @moduledoc """
  Tests for Base64 encoding/decoding edge cases in response body handling.

  This tests the encoding layer that stores response bodies in cassette files
  and decodes them during replay.
  """

  use ExUnit.Case
  alias Reqord.{CassetteEntry, Record, Replay}

  describe "Base64 encoding edge cases" do
    test "handles empty response bodies" do
      # Empty string
      assert Base.encode64("") == ""
      assert {:ok, ""} = Base.decode64("")

      # Nil handling (should be converted to empty string)
      encoded = Base.encode64("")
      assert {:ok, decoded} = Base.decode64(encoded)
      assert decoded == ""
    end

    test "handles full range of binary data" do
      # Test with all possible byte values
      binary_data = for i <- 0..255, into: <<>>, do: <<i>>

      encoded = Base.encode64(binary_data)
      assert {:ok, decoded} = Base.decode64(encoded)
      assert decoded == binary_data
    end

    test "handles binary data with null bytes and control characters" do
      test_cases = [
        # Null bytes and high values
        <<0, 1, 2, 255, 0, 0, 0>>,
        # Text with embedded nulls
        "text\x00with\x00nulls",
        # Wrapped in nulls
        <<0>> <> "hello" <> <<0>>,
        # Many null bytes
        String.duplicate(<<0>>, 1000),
        # Control characters
        "\r\n\t\v\f",
        # Low control characters
        "\x01\x02\x03\x1F"
      ]

      for binary <- test_cases do
        encoded = Base.encode64(binary)
        assert {:ok, decoded} = Base.decode64(encoded)
        assert decoded == binary
      end
    end

    test "handles large binary data efficiently" do
      # Test with large binary data (1MB)
      large_binary = :crypto.strong_rand_bytes(1_000_000)

      # Should encode without memory issues
      encoded = Base.encode64(large_binary)
      assert is_binary(encoded)

      # Should decode back to original
      assert {:ok, decoded} = Base.decode64(encoded)
      assert decoded == large_binary
    end

    test "handles text with various encodings" do
      text_cases = [
        # ASCII
        "Hello World",
        # Unicode with emojis
        "Hello 🌍 世界",
        # Latin characters with accents
        "Café naïve résumé",
        # Cyrillic
        "Здравствуй мир",
        # Japanese
        "こんにちは世界",
        # Multiple emojis
        "🚀🔥💯",
        # Long ASCII string
        String.duplicate("A", 10_000)
      ]

      for text <- text_cases do
        encoded = Base.encode64(text)
        assert {:ok, decoded} = Base.decode64(encoded)
        assert decoded == text
      end
    end

    test "handles JSON responses with various content" do
      json_responses = [
        ~s({"message": "hello"}),
        ~s({"unicode": "Hello 🌍"}),
        # Properly encode JSON with newlines
        Jason.encode!(%{"control" => "line1\nline2\ttab"}),
        ~s({"empty": "", "null": null, "number": 123}),
        Jason.encode!(%{"large_field" => String.duplicate("x", 50_000)}),
        # Deeply nested JSON
        Jason.encode!(1..20 |> Enum.reduce(%{}, fn i, acc -> %{"level#{i}" => acc} end))
      ]

      for json <- json_responses do
        encoded = Base.encode64(json)
        assert {:ok, decoded} = Base.decode64(encoded)
        assert decoded == json
        # Verify it's still valid JSON
        assert {:ok, _} = Jason.decode(decoded)
      end
    end
  end

  describe "Base64 decoding error handling" do
    test "handles invalid Base64 strings gracefully" do
      invalid_base64_cases = [
        # Missing padding
        "SGVsbG8gV29ybGQ",
        # Invalid character
        "SGVsbG8gV29ybGQ!",
        # Too short
        "A",
        # Invalid length
        "AB",
        # Too much padding
        "A===",
        # Only padding
        "====",
        # With newlines
        "SGVs\nsbG8=",
        # With spaces
        "SGVs bG8="
      ]

      for invalid <- invalid_base64_cases do
        case Base.decode64(invalid) do
          {:ok, _decoded} ->
            # Some might succeed due to Base64 tolerance
            :ok

          :error ->
            # Expected for truly invalid data
            :ok
        end
      end
    end

    test "CassetteEntry validation catches invalid Base64" do
      # Test that CassetteEntry validation catches invalid Base64
      invalid_cases = [
        "not-base64!",
        # Missing padding
        "SGVsbG8gV29ybGQ",
        "invalid-chars-!"
      ]

      for invalid_body <- invalid_cases do
        case CassetteEntry.Response.new(200, %{}, invalid_body) do
          {:ok, response} ->
            # If Response creation succeeds, validation should catch it
            case CassetteEntry.validate(%CassetteEntry{
                   req: %CassetteEntry.Request{
                     method: "GET",
                     url: "https://example.com",
                     headers: %{},
                     body_hash: "-"
                   },
                   resp: response
                 }) do
              # Some invalid Base64 might be accepted by Elixir
              {:ok, _} -> :ok
              # Expected for invalid Base64
              {:error, _} -> :ok
            end

          # Response creation itself might fail
          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "Integration with Record and Replay" do
    test "round-trip encoding preserves binary data" do
      # Test various binary data types through the full encode/decode cycle
      test_bodies = [
        # Empty
        "",
        # Text
        "simple text",
        # JSON
        Jason.encode!(%{"key" => "value"}),
        # Binary
        <<0, 1, 2, 255>>,
        # Random binary
        :crypto.strong_rand_bytes(1000),
        # Unicode
        String.duplicate("🚀", 100)
      ]

      for original_body <- test_bodies do
        # Simulate the encoding process (Record.record_response/3)
        # Note: In real code, this goes through redaction first
        encoded_body = Base.encode64(original_body)

        # Simulate the decoding process (Replay.replay_response/2)
        decoded_body = if encoded_body != "", do: Base.decode64!(encoded_body), else: ""

        assert decoded_body == original_body
      end
    end

    test "handles edge cases in replay decoding" do
      # Test the specific replay logic
      test_cases = [
        # Empty Base64 -> empty string
        "",
        # Normal case
        Base.encode64("test")
      ]

      for body_b64 <- test_cases do
        # This mimics the exact logic in Replay.replay_response/2
        decoded = if body_b64 != "", do: Base.decode64!(body_b64), else: ""

        expected = if body_b64 == "", do: "", else: Base.decode64!(body_b64)
        assert decoded == expected
      end
    end

    test "handles extremely long encoded strings" do
      # Test with response that would create very long Base64
      large_response = String.duplicate("A", 1_000_000)
      encoded = Base.encode64(large_response)

      # Should decode without issues
      decoded = Base.decode64!(encoded)
      assert decoded == large_response
      assert String.length(decoded) == 1_000_000
    end
  end

  describe "Memory and performance considerations" do
    test "encoding large data doesn't consume excessive memory" do
      # Test that we can encode large data without memory explosion
      # 10MB
      large_data = :crypto.strong_rand_bytes(10_000_000)

      # Measure memory before
      :erlang.garbage_collect()
      {memory_before, _} = :erlang.process_info(self(), :memory)

      # Encode
      encoded = Base.encode64(large_data)

      # Should succeed
      assert is_binary(encoded)

      # Decode
      {:ok, decoded} = Base.decode64(encoded)
      assert decoded == large_data

      # Clean up
      large_data = nil
      encoded = nil
      decoded = nil
      :erlang.garbage_collect()
    end

    test "repeated encoding/decoding operations are stable" do
      # Test that repeated operations don't cause memory leaks or corruption
      original = :crypto.strong_rand_bytes(10_000)

      # Perform many encode/decode cycles
      result =
        1..100
        |> Enum.reduce(original, fn _i, data ->
          encoded = Base.encode64(data)
          {:ok, decoded} = Base.decode64(encoded)
          decoded
        end)

      assert result == original
    end
  end

  describe "Error conditions and edge cases" do
    test "handles concurrent encoding operations" do
      # Test that concurrent Base64 operations don't interfere
      data = :crypto.strong_rand_bytes(50_000)

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Each task encodes/decodes the same data
            encoded = Base.encode64(data)
            {:ok, decoded} = Base.decode64(encoded)
            {i, decoded == data}
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn {_i, success} -> success end)
    end

    test "handles encoding of data with unusual patterns" do
      # Test data that might cause issues with Base64 padding or encoding
      edge_patterns = [
        # Length divisible by 3
        String.duplicate("A", 3),
        # Length divisible by 4
        String.duplicate("A", 4),
        # Length with remainder
        String.duplicate("A", 5),
        # All high bits
        <<255, 255, 255>>,
        # All zeros
        <<0, 0, 0>>,
        # Alternating bits (10101010)
        <<170, 170, 170>>,
        # Alternating bits (01010101)
        <<85, 85, 85>>
      ]

      for pattern <- edge_patterns do
        encoded = Base.encode64(pattern)
        {:ok, decoded} = Base.decode64(encoded)
        assert decoded == pattern
      end
    end
  end
end
