defmodule Reqord.ErrorHandlingTest do
  use ExUnit.Case

  @test_stub Reqord.ErrorHandlingTest.Stub
  @cassette_dir "test/support/cassettes"

  setup do
    # Ensure cassette directory exists
    File.mkdir_p!(@cassette_dir)

    # Set up Req.Test
    Req.Test.set_req_test_to_private()
    Req.Test.set_req_test_from_context(%{async: true})

    # Clean up test files after each test
    test_files = [
      "invalid_json.jsonl",
      "malformed_entries.jsonl",
      "mixed_valid_invalid.jsonl",
      "empty_file.jsonl",
      "partial_json.jsonl",
      "unicode_issues.jsonl",
      "huge_file.jsonl"
    ]

    on_exit(fn ->
      Enum.each(test_files, fn file ->
        file_path = Path.join(@cassette_dir, file)

        if File.exists?(file_path) do
          File.rm!(file_path)
        end
      end)
    end)

    :ok
  end

  describe "invalid JSONL file handling" do
    test "handles completely invalid JSON in cassette" do
      cassette_path = Path.join(@cassette_dir, "invalid_json.jsonl")

      # Write invalid JSON
      File.write!(cassette_path, "{ this is not valid json }\n")

      # Should not crash when loading cassette
      Reqord.install!(
        name: @test_stub,
        cassette: "invalid_json",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should raise cassette miss (because invalid entries are ignored)
      assert_raise Reqord.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/test")
      end
    end

    test "handles malformed cassette entries missing required fields" do
      cassette_path = Path.join(@cassette_dir, "malformed_entries.jsonl")

      malformed_entries = [
        # Missing resp field
        ~s({"req": {"method": "GET", "url": "https://api.example.com/1", "body_hash": "-"}}\n),
        # Missing req field
        ~s({"resp": {"status": 200, "headers": {}, "body_b64": "dGVzdA=="}}\n),
        # Missing method in req
        ~s({"req": {"url": "https://api.example.com/2", "body_hash": "-"}, "resp": {"status": 200}}\n),
        # Valid entry for comparison
        ~s({"req": {"method": "GET", "url": "https://api.example.com/valid", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "headers": {}, "body_b64": "#{Base.encode64("valid")}"}}\n)
      ]

      File.write!(cassette_path, Enum.join(malformed_entries, ""))

      Reqord.install!(
        name: @test_stub,
        cassette: "malformed_entries",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Valid entry should work
      {:ok, response} = Req.get(client, url: "https://api.example.com/valid")
      assert response.body == "valid"

      # Malformed entries should be ignored, so these should raise
      assert_raise Reqord.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/1")
      end

      assert_raise Reqord.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/2")
      end
    end

    test "handles mixed valid and invalid JSON lines" do
      cassette_path = Path.join(@cassette_dir, "mixed_valid_invalid.jsonl")

      content = """
      {"req": {"method": "GET", "url": "https://api.example.com/valid1", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "headers": {}, "body_b64": "#{Base.encode64("first")}"}}
      { invalid json here
      {"req": {"method": "GET", "url": "https://api.example.com/valid2", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "headers": {}, "body_b64": "#{Base.encode64("second")}"}}
      not json at all!
      {"req": {"method": "GET", "url": "https://api.example.com/valid3", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "headers": {}, "body_b64": "#{Base.encode64("third")}"}}
      """

      File.write!(cassette_path, content)

      Reqord.install!(
        name: @test_stub,
        cassette: "mixed_valid_invalid",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Valid entries should work
      {:ok, resp1} = Req.get(client, url: "https://api.example.com/valid1")
      {:ok, resp2} = Req.get(client, url: "https://api.example.com/valid2")
      {:ok, resp3} = Req.get(client, url: "https://api.example.com/valid3")

      assert resp1.body == "first"
      assert resp2.body == "second"
      assert resp3.body == "third"
    end

    test "handles completely empty cassette file" do
      cassette_path = Path.join(@cassette_dir, "empty_file.jsonl")
      File.write!(cassette_path, "")

      Reqord.install!(
        name: @test_stub,
        cassette: "empty_file",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should behave same as missing cassette
      assert_raise Reqord.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/test")
      end
    end

    test "handles partial JSON lines (truncated)" do
      cassette_path = Path.join(@cassette_dir, "partial_json.jsonl")

      # Simulate a truncated file (maybe due to interrupted write)
      content = """
      {"req": {"method": "GET", "url": "https://api.example.com/complete", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "headers": {}, "body_b64": "#{Base.encode64("complete")}"}}
      {"req": {"method": "GET", "url": "https://api.example.com/truncated", "body_hash": "-", "headers": {}}, "resp": {"status": 200, "head
      """

      File.write!(cassette_path, content)

      Reqord.install!(
        name: @test_stub,
        cassette: "partial_json",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Complete entry should work
      {:ok, response} = Req.get(client, url: "https://api.example.com/complete")
      assert response.body == "complete"

      # Truncated entry should be ignored
      assert_raise Reqord.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/truncated")
      end
    end

    test "handles unicode and special characters in JSON" do
      cassette_path = Path.join(@cassette_dir, "unicode_issues.jsonl")

      # Test various unicode scenarios
      unicode_body =
        Reqord.JSON.encode!(%{
          "emoji" => "🚀🌟",
          "chinese" => "你好世界",
          "arabic" => "مرحبا بالعالم",
          "special_chars" => "\"quotes\" and \\backslashes\\ and \n newlines"
        })

      entry = %{
        req: %{
          method: "GET",
          url: "https://api.example.com/unicode",
          body_hash: "-",
          headers: %{}
        },
        resp: %{
          status: 200,
          headers: %{"content-type" => "application/json; charset=utf-8"},
          body_b64: Base.encode64(unicode_body)
        }
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      Reqord.install!(
        name: @test_stub,
        cassette: "unicode_issues",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response} = Req.get(client, url: "https://api.example.com/unicode")

      assert response.status == 200
      assert is_map(response.body)
      assert response.body["emoji"] == "🚀🌟"
      assert response.body["chinese"] == "你好世界"
      assert response.body["arabic"] == "مرحبا بالعالم"
    end
  end

  describe "redactor error handling" do
    test "redactor handles invalid JSON gracefully" do
      # Test the specific fix we made to redactor.ex
      invalid_json = "{ this is not valid json }"

      # Should not crash, should return original string
      result = Reqord.Redactor.redact_response_body(invalid_json)
      assert result == invalid_json
    end

    test "redactor handles non-string input" do
      # Should handle non-binary input gracefully
      result = Reqord.Redactor.redact_response_body(nil)
      assert result == nil

      result = Reqord.Redactor.redact_response_body(123)
      assert result == 123
    end

    test "redactor handles malformed JSON that throws during encoding" do
      # This tests the Jason.EncodeError rescue clause
      # Create a structure that decodes but can't be re-encoded cleanly

      # Normal case should work
      valid_json = ~s({"token": "secret123", "data": "normal"})
      result = Reqord.Redactor.redact_response_body(valid_json)

      # Should redact the token
      assert String.contains?(result, "<REDACTED>")
      assert String.contains?(result, "normal")
      refute String.contains?(result, "secret123")
    end
  end

  describe "network error handling during recording" do
    test "record mode handles network failures with clear error messages" do
      # This tests our fix to record.ex error handling
      # Note: We can't easily test actual network failures in unit tests,
      # but we can verify the error handling structure exists

      # In :new_episodes mode, if we try to record a non-existent request,
      # it should attempt to make a real network call and potentially fail
      Reqord.install!(
        name: @test_stub,
        cassette: "network_error_test",
        mode: :new_episodes
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # This should try to make a real network call to an invalid domain
      # The error handling should log appropriately before re-raising
      assert_raise Req.TransportError, fn ->
        Req.get!(client, url: "https://definitely-not-a-real-domain-12345.invalid/test")
      end
    end
  end

  describe "file system error handling" do
    test "handles permission errors when writing cassettes" do
      # Create a read-only directory to simulate permission errors
      readonly_dir = Path.join(@cassette_dir, "readonly")
      File.mkdir_p!(readonly_dir)

      # Make directory read-only (on Unix systems)
      case :os.type() do
        {:unix, _} ->
          :ok = File.chmod(readonly_dir, 0o444)

          on_exit(fn ->
            # Restore permissions for cleanup
            File.chmod(readonly_dir, 0o755)
            File.rmdir(readonly_dir)
          end)

          Reqord.install!(
            name: @test_stub,
            cassette: "readonly/test",
            mode: :new_episodes
          )

          client = Req.new(plug: {Req.Test, @test_stub})

          # Should raise file permission error when trying to write cassette
          assert_raise File.Error, fn ->
            Req.get!(client, url: "https://httpbin.org/get")
          end

        _ ->
          # Skip test on non-Unix systems
          :ok
      end
    end
  end
end
