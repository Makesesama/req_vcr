defmodule Reqord.JSONLTest do
  use ExUnit.Case

  @cassette_dir "test/support/cassettes"

  setup do
    # Ensure cassette directory exists
    File.mkdir_p!(@cassette_dir)

    # Clean up temporary test files, but preserve fixtures and ExampleAPI
    on_exit(fn ->
      File.ls!(@cassette_dir)
      # Keep permanent test fixtures and ExampleAPI cassettes
      |> Enum.reject(&(&1 in ["fixtures", "ExampleAPI"]))
      |> Enum.each(fn file ->
        file_path = Path.join(@cassette_dir, file)

        if File.dir?(file_path) do
          File.rm_rf!(file_path)
        else
          File.rm!(file_path)
        end
      end)
    end)

    :ok
  end

  describe "cassette JSONL format" do
    test "cassettes are valid JSONL with one JSON object per line" do
      cassette_path = Path.join(@cassette_dir, "jsonl_test.jsonl")

      # Create a cassette with multiple entries
      entry1 = %{
        req: %{method: "GET", url: "https://api.example.com/1", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("first")}
      }

      entry2 = %{
        req: %{method: "GET", url: "https://api.example.com/2", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("second")}
      }

      File.write!(cassette_path, Jason.encode!(entry1) <> "\n" <> Jason.encode!(entry2) <> "\n")

      # Read and verify JSONL format
      lines = File.stream!(cassette_path) |> Enum.to_list()

      # Should have 2 lines
      assert length(lines) == 2

      # Each line should be valid JSON
      Enum.each(lines, fn line ->
        trimmed = String.trim(line)
        assert {:ok, _decoded} = Jason.decode(trimmed)

        # Line should not contain internal newlines (proper JSONL)
        assert trimmed == line |> String.trim_trailing("\n")
      end)

      # Verify we can decode both entries
      [line1, line2] = lines
      assert {:ok, decoded1} = Jason.decode(String.trim(line1))
      assert {:ok, decoded2} = Jason.decode(String.trim(line2))

      assert decoded1["req"]["url"] == "https://api.example.com/1"
      assert decoded2["req"]["url"] == "https://api.example.com/2"
    end

    test "cassette entries do not contain newlines within JSON" do
      entry = %{
        req: %{
          method: "POST",
          url: "https://api.example.com/test",
          body_hash: "abc123",
          headers: %{"authorization" => "Bearer token"}
        },
        resp: %{
          status: 201,
          headers: %{"content-type" => "application/json"},
          body_b64: Base.encode64(~s({"result":"success"}))
        }
      }

      # Test JSON encoding directly without file I/O
      encoded = Jason.encode!(entry)
      lines = String.split(encoded <> "\n", "\n", trim: true)

      # Should be exactly one line
      assert length(lines) == 1

      # The line should be valid JSON without internal newlines
      [line] = lines
      assert {:ok, _decoded} = Jason.decode(line)
      refute String.contains?(line, "\n")
    end

    test "multiple entries are stored on separate lines" do
      cassette_path = Path.join(@cassette_dir, "multi_line_test.jsonl")

      entries = [
        %{
          req: %{
            method: "GET",
            url: "https://api.example.com/users",
            body_hash: "-",
            headers: %{}
          },
          resp: %{status: 200, headers: %{}, body_b64: Base.encode64("users")}
        },
        %{
          req: %{
            method: "GET",
            url: "https://api.example.com/posts",
            body_hash: "-",
            headers: %{}
          },
          resp: %{status: 200, headers: %{}, body_b64: Base.encode64("posts")}
        },
        %{
          req: %{
            method: "POST",
            url: "https://api.example.com/comments",
            body_hash: "abc",
            headers: %{}
          },
          resp: %{status: 201, headers: %{}, body_b64: Base.encode64("created")}
        }
      ]

      # Write entries to file
      content = Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
      File.write!(cassette_path, content)

      # Read back and verify
      loaded_entries =
        cassette_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.map(&Jason.decode!/1)
        |> Enum.to_list()

      assert length(loaded_entries) == 3
      assert Enum.at(loaded_entries, 0)["req"]["url"] == "https://api.example.com/users"
      assert Enum.at(loaded_entries, 1)["req"]["url"] == "https://api.example.com/posts"
      assert Enum.at(loaded_entries, 2)["req"]["url"] == "https://api.example.com/comments"
      assert Enum.at(loaded_entries, 2)["req"]["method"] == "POST"
    end

    test "empty lines are ignored when loading cassettes" do
      cassette_path = Path.join(@cassette_dir, "empty_lines_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/test", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("test")}
      }

      # Write with empty lines
      content = "\n" <> Jason.encode!(entry) <> "\n\n" <> Jason.encode!(entry) <> "\n\n"
      File.write!(cassette_path, content)

      # Load entries (should ignore empty lines)
      loaded_entries =
        cassette_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.map(&Jason.decode!/1)
        |> Enum.to_list()

      # Should only have the 2 actual entries, empty lines ignored
      assert length(loaded_entries) == 2
    end

    test "base64 encoded response bodies are properly handled" do
      original_body = ~s({"message": "Hello, World!", "unicode": "🌍"})
      encoded_body = Base.encode64(original_body)

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/hello", body_hash: "-", headers: %{}},
        resp: %{
          status: 200,
          headers: %{"content-type" => "application/json; charset=utf-8"},
          body_b64: encoded_body
        }
      }

      # Encode to JSON and verify round-trip
      json_line = Jason.encode!(entry)
      {:ok, decoded_entry} = Jason.decode(json_line)

      # Verify base64 body is preserved
      assert decoded_entry["resp"]["body_b64"] == encoded_body

      # Verify we can decode the body back
      decoded_body = Base.decode64!(decoded_entry["resp"]["body_b64"])
      assert decoded_body == original_body

      # Verify it's valid JSON with Unicode
      {:ok, parsed_body} = Jason.decode(decoded_body)
      assert parsed_body["message"] == "Hello, World!"
      assert parsed_body["unicode"] == "🌍"
    end
  end
end
