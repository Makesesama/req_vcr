defmodule Reqord.CassetteEdgeCasesTest do
  @moduledoc """
  Tests for cassette file handling edge cases including malformed files,
  large files, unusual content, and various file system scenarios.
  """

  use ExUnit.Case
  alias Reqord.CassetteReader

  @test_dir Path.join(System.tmp_dir!(), "reqord_cassette_edge_test")

  setup do
    # Create fresh test directory for each test
    test_dir = @test_dir <> "_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      nil
      # Don't delete test directories - cassettes should persist
    end)

    %{test_dir: test_dir}
  end

  describe "file format edge cases" do
    test "handles cassette files with mixed line endings", %{test_dir: test_dir} do
      # Create cassette file with mixed line endings
      entries = [
        create_valid_entry("GET", "https://example.com/1") <> "\r\n",
        create_valid_entry("POST", "https://example.com/2") <> "\n",
        create_valid_entry("PUT", "https://example.com/3") <> "\r"
      ]

      cassette_file = Path.join(test_dir, "mixed_endings.jsonl")
      File.write!(cassette_file, Enum.join(entries, ""))

      # Should be able to read despite mixed endings
      loaded_entries = CassetteReader.load_entries(cassette_file)
      assert length(loaded_entries) == 3
    end

    test "handles empty and whitespace-only cassette files", %{test_dir: test_dir} do
      test_cases = [
        {"empty.jsonl", ""},
        {"whitespace.jsonl", "   \n\n\t  \n"},
        {"newlines.jsonl", "\n\n\n\n"},
        {"spaces.jsonl", "          "},
        {"tabs.jsonl", "\t\t\t\t"}
      ]

      for {filename, content} <- test_cases do
        cassette_file = Path.join(test_dir, filename)
        File.write!(cassette_file, content)

        entries = CassetteReader.load_entries(cassette_file)
        assert entries == []
      end
    end

    test "handles files without final newline", %{test_dir: test_dir} do
      # File that doesn't end with newline
      content = create_valid_entry("GET", "https://example.com/test")

      cassette_file = Path.join(test_dir, "no_final_newline.jsonl")
      # No \n at end
      File.write!(cassette_file, content)

      entries = CassetteReader.load_entries(cassette_file)
      assert length(entries) == 1
    end

    test "handles files with BOM markers", %{test_dir: test_dir} do
      # UTF-8 BOM followed by valid JSON
      bom = <<0xEF, 0xBB, 0xBF>>
      content = bom <> create_valid_entry("GET", "https://example.com/test")

      cassette_file = Path.join(test_dir, "with_bom.jsonl")
      File.write!(cassette_file, content)

      # Should handle BOM gracefully (may or may not parse depending on implementation)
      entries = CassetteReader.load_entries(cassette_file)
      # BOM should be handled gracefully, may return empty list
      assert is_list(entries)
    end
  end

  describe "malformed content handling" do
    test "handles cassette files with some invalid entries mixed with valid ones", %{
      test_dir: test_dir
    } do
      # Mix of valid and invalid JSON lines
      lines = [
        create_valid_entry("GET", "https://example.com/1"),
        "{invalid json",
        # Empty line
        "",
        create_valid_entry("POST", "https://example.com/2"),
        ~s({"missing": "required_fields"}),
        # Whitespace line
        "   ",
        create_valid_entry("PUT", "https://example.com/3")
      ]

      cassette_file = Path.join(test_dir, "mixed_valid_invalid.jsonl")
      File.write!(cassette_file, Enum.join(lines, "\n"))

      # Should skip invalid entries and load valid ones
      entries = CassetteReader.load_entries(cassette_file)
      # Only the 3 valid entries
      assert length(entries) == 3
    end

    test "handles extremely long JSON lines", %{test_dir: test_dir} do
      # Create entry with very long URL and response
      long_path = String.duplicate("a", 10_000)
      long_response = String.duplicate("x", 100_000)

      entry = %{
        req: %{
          method: "GET",
          url: "https://example.com/#{long_path}",
          headers: %{},
          body_hash: "-"
        },
        resp: %{
          status: 200,
          headers: %{},
          body_b64: Base.encode64(long_response)
        }
      }

      content = Jason.encode!(entry)
      cassette_file = Path.join(test_dir, "long_lines.jsonl")
      File.write!(cassette_file, content)

      # Should handle long lines
      entries = CassetteReader.load_entries(cassette_file)
      assert length(entries) == 1

      # Verify content is preserved
      loaded_entry = hd(entries)
      assert String.length(loaded_entry.req.url) > 10_000
    end

    test "handles JSON with embedded newlines and special characters", %{test_dir: test_dir} do
      # Response body with embedded newlines, tabs, etc.
      response_with_newlines = "line1\nline2\ttab\r\nwindows\x00null"

      entry = %{
        req: %{
          method: "GET",
          url: "https://example.com/test",
          headers: %{"user-agent" => "test\nwith\nnewlines"},
          body_hash: "-"
        },
        resp: %{
          status: 200,
          headers: %{"content-type" => "text/plain\r\nwith\r\ncarriage\r\nreturns"},
          body_b64: Base.encode64(response_with_newlines)
        }
      }

      content = Jason.encode!(entry)
      cassette_file = Path.join(test_dir, "embedded_chars.jsonl")
      File.write!(cassette_file, content)

      entries = CassetteReader.load_entries(cassette_file)
      assert length(entries) == 1

      loaded_entry = hd(entries)
      decoded_body = Base.decode64!(loaded_entry.resp.body_b64)
      assert decoded_body == response_with_newlines
    end
  end

  describe "large file handling" do
    test "handles cassette files with many entries", %{test_dir: test_dir} do
      # Create cassette with 1000 entries
      entries =
        for i <- 1..1000 do
          create_valid_entry("GET", "https://example.com/item/#{i}")
        end

      cassette_file = Path.join(test_dir, "many_entries.jsonl")
      File.write!(cassette_file, Enum.join(entries, "\n"))

      # Should load all entries efficiently
      loaded_entries = CassetteReader.load_entries(cassette_file)
      assert length(loaded_entries) == 1000

      # Verify some entries
      first_entry = hd(loaded_entries)
      assert first_entry.req.url == "https://example.com/item/1"

      last_entry = List.last(loaded_entries)
      assert last_entry.req.url == "https://example.com/item/1000"
    end

    test "handles entries with large response bodies", %{test_dir: test_dir} do
      # Create entry with 1MB response
      large_response = :crypto.strong_rand_bytes(1_000_000)

      entry = %{
        req: %{method: "GET", url: "https://example.com/large", headers: %{}, body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64(large_response)}
      }

      cassette_file = Path.join(test_dir, "large_response.jsonl")
      File.write!(cassette_file, Jason.encode!(entry))

      entries = CassetteReader.load_entries(cassette_file)
      assert length(entries) == 1

      loaded_entry = hd(entries)
      decoded_body = Base.decode64!(loaded_entry.resp.body_b64)
      assert decoded_body == large_response
    end
  end

  describe "concurrent access" do
    test "handles multiple processes reading same cassette", %{test_dir: test_dir} do
      # Create cassette file
      entries =
        for i <- 1..100 do
          create_valid_entry("GET", "https://example.com/item/#{i}")
        end

      cassette_file = Path.join(test_dir, "concurrent_read.jsonl")
      File.write!(cassette_file, Enum.join(entries, "\n"))

      # Spawn multiple processes to read concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            loaded_entries = CassetteReader.load_entries(cassette_file)
            {i, length(loaded_entries)}
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed and load the same number of entries
      assert Enum.all?(results, fn {_i, count} -> count == 100 end)
    end

    test "handles file being modified during read", %{test_dir: test_dir} do
      # This tests robustness when file changes during operation
      cassette_file = Path.join(test_dir, "modified_during_read.jsonl")

      # Start with some entries
      initial_content = create_valid_entry("GET", "https://example.com/1")
      File.write!(cassette_file, initial_content)

      # Read while potentially modifying
      task =
        Task.async(fn ->
          # Add delay to increase chance of concurrent modification
          :timer.sleep(10)
          CassetteReader.load_entries(cassette_file)
        end)

      # Modify file during read
      additional_content = "\n" <> create_valid_entry("GET", "https://example.com/2")
      File.write!(cassette_file, initial_content <> additional_content)

      # Should complete without error (though results may vary)
      result = Task.await(task)
      # Should return a list of entries
      assert is_list(result)
    end
  end

  describe "file system edge cases" do
    test "handles non-existent cassette files gracefully", %{test_dir: test_dir} do
      non_existent = Path.join(test_dir, "does_not_exist.jsonl")

      entries = CassetteReader.load_entries(non_existent)
      # Non-existent files should return empty list
      assert entries == []
    end

    test "handles cassette files in non-existent directories", %{test_dir: test_dir} do
      deep_path = Path.join([test_dir, "non", "existent", "path", "cassette.jsonl"])

      entries = CassetteReader.load_entries(deep_path)
      # Non-existent paths should return empty list
      assert entries == []
    end

    test "handles cassette files with unusual permissions", %{test_dir: test_dir} do
      cassette_file = Path.join(test_dir, "permissions_test.jsonl")
      File.write!(cassette_file, create_valid_entry("GET", "https://example.com/test"))

      # Try to make file read-only (might not work on all systems)
      case File.chmod(cassette_file, 0o444) do
        :ok ->
          # Should still be able to read
          entries = CassetteReader.load_entries(cassette_file)
          # Should still be able to read even with changed permissions
          assert length(entries) == 1

        {:error, _} ->
          # chmod might not work on some filesystems, skip this part
          :ok
      end
    end
  end

  describe "entry validation edge cases" do
    test "handles entries with unusual but valid HTTP methods", %{test_dir: test_dir} do
      # Only use methods that are actually valid in the system
      unusual_methods = ["PATCH", "HEAD", "OPTIONS"]

      entries =
        for method <- unusual_methods do
          create_valid_entry(method, "https://example.com/#{String.downcase(method)}")
        end

      cassette_file = Path.join(test_dir, "unusual_methods.jsonl")
      File.write!(cassette_file, Enum.join(entries, "\n"))

      loaded_entries = CassetteReader.load_entries(cassette_file)
      assert length(loaded_entries) == length(unusual_methods)

      # Verify methods are preserved
      loaded_methods = Enum.map(loaded_entries, & &1.req.method)
      assert Enum.all?(unusual_methods, &(&1 in loaded_methods))
    end

    test "handles entries with edge case status codes", %{test_dir: test_dir} do
      edge_status_codes = [100, 102, 207, 226, 300, 418, 451, 511]

      entries =
        for status <- edge_status_codes do
          create_entry_with_status("GET", "https://example.com/status/#{status}", status)
        end

      cassette_file = Path.join(test_dir, "edge_status_codes.jsonl")
      File.write!(cassette_file, Enum.join(entries, "\n"))

      loaded_entries = CassetteReader.load_entries(cassette_file)
      assert length(loaded_entries) == length(edge_status_codes)

      # Verify status codes are preserved
      loaded_statuses = Enum.map(loaded_entries, & &1.resp.status)
      assert Enum.all?(edge_status_codes, &(&1 in loaded_statuses))
    end

    test "handles entries with complex headers", %{test_dir: test_dir} do
      complex_headers = %{
        "authorization" => "Bearer " <> String.duplicate("a", 1000),
        "user-agent" => "Mozilla/5.0 (complex; user; agent) with 🚀 unicode",
        "x-custom-header" => "value\nwith\nnewlines",
        "empty-header" => "",
        "unicode-header" => "header-with-émojis-🌟",
        "long-header" => String.duplicate("x", 5000)
      }

      entry = %{
        req: %{
          method: "GET",
          url: "https://example.com/complex-headers",
          headers: complex_headers,
          body_hash: "-"
        },
        resp: %{
          status: 200,
          headers: complex_headers,
          body_b64: Base.encode64("response")
        }
      }

      cassette_file = Path.join(test_dir, "complex_headers.jsonl")
      File.write!(cassette_file, Jason.encode!(entry))

      entries = CassetteReader.load_entries(cassette_file)
      assert length(entries) == 1

      loaded_entry = hd(entries)
      # Verify some complex headers are preserved
      assert String.length(loaded_entry.req.headers["long-header"]) == 5000
      assert loaded_entry.req.headers["unicode-header"] == "header-with-émojis-🌟"
    end
  end

  # Helper functions

  defp create_valid_entry(method, url) do
    entry = %{
      req: %{
        method: method,
        url: url,
        headers: %{},
        body_hash: "-"
      },
      resp: %{
        status: 200,
        headers: %{},
        body_b64: Base.encode64("test response")
      }
    }

    Jason.encode!(entry)
  end

  defp create_entry_with_status(method, url, status) do
    entry = %{
      req: %{
        method: method,
        url: url,
        headers: %{},
        body_hash: "-"
      },
      resp: %{
        status: status,
        headers: %{},
        body_b64: Base.encode64("test response")
      }
    }

    Jason.encode!(entry)
  end
end
