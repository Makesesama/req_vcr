defmodule Reqord.RedactorTest do
  use ExUnit.Case

  alias Reqord.Redactor

  describe "redact_headers/1" do
    test "redacts authorization headers" do
      headers = [{"authorization", "Bearer secret123"}, {"content-type", "application/json"}]
      result = Redactor.redact_headers(headers)

      assert result == %{
               "authorization" => "<REDACTED>",
               "content-type" => "application/json"
             }
    end

    test "redacts various auth headers" do
      headers = [
        {"authorization", "Bearer token"},
        {"x-api-key", "secret-key"},
        {"x-auth-token", "auth-token"},
        {"cookie", "session=abc123"},
        {"user-agent", "MyApp/1.0"}
      ]

      result = Redactor.redact_headers(headers)

      assert result["authorization"] == "<REDACTED>"
      assert result["x-api-key"] == "<REDACTED>"
      assert result["x-auth-token"] == "<REDACTED>"
      assert result["cookie"] == "<REDACTED>"
      assert result["user-agent"] == "MyApp/1.0"
    end

    test "works with map input" do
      headers = %{"authorization" => "Bearer token", "content-type" => "application/json"}
      result = Redactor.redact_headers(headers)

      assert result == %{
               "authorization" => "<REDACTED>",
               "content-type" => "application/json"
             }
    end

    test "redacts headers with extremely long and short tokens" do
      long_token = String.duplicate("a", 256)
      short_token = "abc"

      headers = [
        {"authorization", "Bearer #{long_token}"},
        {"x-api-key", short_token},
        {"x-auth-token", String.duplicate("x", 512)},
        {"content-type", "application/json"}
      ]

      result = Redactor.redact_headers(headers)

      # All auth headers should be redacted regardless of token length
      assert result["authorization"] == "<REDACTED>"
      assert result["x-api-key"] == "<REDACTED>"
      assert result["x-auth-token"] == "<REDACTED>"
      assert result["content-type"] == "application/json"
    end
  end

  describe "redact_url/1" do
    test "redacts auth query parameters" do
      url = "https://api.example.com/users?token=secret&name=john&api_key=mykey"
      result = Redactor.redact_url(url)

      # URI.encode_query encodes the angle brackets
      assert result =~ "token=%3CREDACTED%3E"
      assert result =~ "api_key=%3CREDACTED%3E"
      assert result =~ "name=john"
    end

    test "handles URLs without query parameters" do
      url = "https://api.example.com/users"
      result = Redactor.redact_url(url)

      assert result == url
    end

    test "redacts various auth parameter names" do
      url =
        "https://api.example.com/data?access_token=secret&refresh_token=refresh&jwt=token&normal=value"

      result = Redactor.redact_url(url)

      assert result =~ "access_token=%3CREDACTED%3E"
      assert result =~ "refresh_token=%3CREDACTED%3E"
      assert result =~ "jwt=%3CREDACTED%3E"
      assert result =~ "normal=value"
    end

    test "redacts extremely long and short tokens in URLs" do
      long_token = String.duplicate("a", 500)
      medium_token = String.duplicate("x", 50)
      short_token = "abc"

      url =
        "https://api.example.com/data?token=#{long_token}&api_key=#{short_token}&access_token=#{medium_token}&user=john"

      result = Redactor.redact_url(url)

      # All auth parameters should be redacted regardless of token length
      assert result =~ "token=%3CREDACTED%3E"
      assert result =~ "api_key=%3CREDACTED%3E"
      assert result =~ "access_token=%3CREDACTED%3E"
      assert result =~ "user=john"
    end

    test "handles edge cases with special characters in tokens" do
      # Token with URL-encoded characters
      url = "https://api.example.com/data?token=abc%20def%2Bghi&normal=value"
      result = Redactor.redact_url(url)

      assert result =~ "token=%3CREDACTED%3E"
      assert result =~ "normal=value"

      # Token with equals signs and ampersands that could confuse parsing
      url = "https://api.example.com/data?api_key=key%3Dwith%26special%3Dchars&data=test"
      result = Redactor.redact_url(url)

      assert result =~ "api_key=%3CREDACTED%3E"
      assert result =~ "data=test"
    end

    test "handles malformed and edge case URLs" do
      # URLs that might cause parsing issues
      edge_case_urls = [
        "https://example.com/path with spaces?token=secret",
        # Empty key
        "https://example.com/?=&token=secret",
        # No value
        "https://example.com/?key&token=secret",
        # Multiple separators
        "https://example.com/?&&&&token=secret",
        # Duplicate keys
        "https://example.com/?key=val&key=val2&token=secret",
        # Unicode
        "https://example.com/路径?token=secret&参数=值"
      ]

      for url <- edge_case_urls do
        result = Redactor.redact_url(url)
        assert is_binary(result)
        # Token should be redacted in all cases
        refute String.contains?(result, "token=secret")
      end
    end

    test "handles extremely long URLs" do
      # Test with URLs longer than typical limits
      long_path = String.duplicate("a", 5_000)
      long_query = String.duplicate("param=value&", 500)

      long_url = "https://example.com/#{long_path}?#{long_query}token=secret&api_key=key"

      # Should redact without crashing
      result = Redactor.redact_url(long_url)
      assert is_binary(result)
      # Auth params should be removed
      refute String.contains?(result, "token=secret")
      refute String.contains?(result, "api_key=key")
    end
  end

  describe "redact_response_body/1" do
    test "redacts JSON response with auth tokens" do
      body = ~s({"access_token": "secret123", "user": {"name": "John"}})
      result = Redactor.redact_response_body(body)

      decoded = Jason.decode!(result)
      assert decoded["access_token"] == "<REDACTED>"
      assert decoded["user"]["name"] == "John"
    end

    test "redacts nested JSON secrets" do
      body = ~s({
        "user": {
          "name": "John",
          "api_key": "secret123",
          "profile": {
            "password": "mysecret"
          }
        },
        "data": "public"
      })

      result = Redactor.redact_response_body(body)
      decoded = Jason.decode!(result)

      assert decoded["user"]["api_key"] == "<REDACTED>"
      assert decoded["user"]["profile"]["password"] == "<REDACTED>"
      assert decoded["user"]["name"] == "John"
      assert decoded["data"] == "public"
    end

    test "redacts Bearer tokens in text responses" do
      body = "Your token is: Bearer abc123def456. Use it wisely."
      result = Redactor.redact_response_body(body)

      assert result == "Your token is: Bearer <REDACTED>. Use it wisely."
    end

    test "redacts long alphanumeric strings" do
      body = "API key: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6 and normal text"
      result = Redactor.redact_response_body(body)

      assert result == "API key: <REDACTED> and normal text"
    end

    test "redacts GitHub tokens" do
      body = "Your GitHub token: ghp_1234567890123456789012345678901234567890"
      result = Redactor.redact_response_body(body)

      assert result == "Your GitHub token: <REDACTED>"
    end

    test "redacts UUIDs (potential session IDs)" do
      body = "Session: 123e4567-e89b-12d3-a456-426614174000"
      result = Redactor.redact_response_body(body)

      assert result == "Session: <REDACTED>"
    end

    test "handles malformed JSON gracefully" do
      body = "{invalid json"
      result = Redactor.redact_response_body(body)

      assert result == body
    end

    test "handles non-string input" do
      assert Redactor.redact_response_body(123) == 123
      assert Redactor.redact_response_body(nil) == nil
    end

    test "redacts really long API tokens" do
      # Test 64-character token
      body = "API key: #{String.duplicate("a", 64)} and normal text"
      result = Redactor.redact_response_body(body)
      assert result == "API key: <REDACTED> and normal text"

      # Test 128-character token
      long_token = String.duplicate("x", 128)
      body = "Token: #{long_token}"
      result = Redactor.redact_response_body(body)
      assert result == "Token: <REDACTED>"

      # Test 256-character token
      very_long_token = String.duplicate("A1b2C3d4", 32)
      body = "Secret: #{very_long_token} end"
      result = Redactor.redact_response_body(body)
      assert result == "Secret: <REDACTED> end"

      # Test 512-character token
      extremely_long_token = String.duplicate("0123456789abcdef", 32)
      body = ~s({"mega_key": "#{extremely_long_token}", "data": "value"})
      result = Redactor.redact_response_body(body)
      decoded = Jason.decode!(result)
      assert decoded["mega_key"] == "<REDACTED>"
      assert decoded["data"] == "value"
    end

    test "redacts really short API tokens at boundary conditions" do
      # Test 31-character token (just below the 32 threshold)
      token_31 = String.duplicate("a", 31)
      body = "Token: #{token_31} text"
      result = Redactor.redact_response_body(body)
      # Should NOT be redacted
      assert result == body

      # Test exactly 32-character token (at threshold)
      token_32 = String.duplicate("b", 32)
      body = "Token: #{token_32} text"
      result = Redactor.redact_response_body(body)
      assert result == "Token: <REDACTED> text"

      # Test 33-character token (just above threshold)
      token_33 = String.duplicate("c", 33)
      body = "Token: #{token_33} text"
      result = Redactor.redact_response_body(body)
      assert result == "Token: <REDACTED> text"
    end

    test "handles mixed length tokens in same response" do
      body = ~s({
        "short_data": "abc123",
        "medium_data": "#{String.duplicate("x", 20)}",
        "long_data": "#{String.duplicate("y", 40)}",
        "very_long_data": "#{String.duplicate("z", 100)}",
        "normal_info": "some value"
      })

      result = Redactor.redact_response_body(body)
      decoded = Jason.decode!(result)

      # Short data should not be redacted by length rule (no sensitive keywords)
      assert decoded["short_data"] == "abc123"
      assert decoded["medium_data"] == String.duplicate("x", 20)
      # Long data should be redacted by length rule
      assert decoded["long_data"] == "<REDACTED>"
      assert decoded["very_long_data"] == "<REDACTED>"
      assert decoded["normal_info"] == "some value"
    end

    test "redacts tokens with special prefixes regardless of length" do
      # GitHub token - should be redacted even if pattern matches
      body = "GitHub: ghp_#{String.duplicate("a", 40)}"
      result = Redactor.redact_response_body(body)
      assert result == "GitHub: <REDACTED>"

      # Stripe secret key - should be redacted
      body = "Stripe: sk_#{String.duplicate("b", 20)}"
      result = Redactor.redact_response_body(body)
      assert result == "Stripe: <REDACTED>"

      # Stripe public key - should be redacted
      body = "Public: pk_#{String.duplicate("c", 15)}"
      result = Redactor.redact_response_body(body)
      assert result == "Public: <REDACTED>"

      # Short Bearer token - should be redacted despite length
      body = "Auth: Bearer abc123"
      result = Redactor.redact_response_body(body)
      assert result == "Auth: Bearer <REDACTED>"
    end

    test "preserves formatting around redacted tokens" do
      # Test with tabs
      body = "Key:\t#{String.duplicate("x", 40)}\tnext"
      result = Redactor.redact_response_body(body)
      assert result == "Key:\t<REDACTED>\tnext"

      # Test with newlines
      body = "Key:\n#{String.duplicate("y", 50)}\nmore"
      result = Redactor.redact_response_body(body)
      assert result == "Key:\n<REDACTED>\nmore"

      # Test with multiple spaces
      body = "Key:   #{String.duplicate("z", 35)}   end"
      result = Redactor.redact_response_body(body)
      assert result == "Key:   <REDACTED>   end"
    end

    test "handles edge cases with numeric and mixed tokens" do
      # Pure numeric long string
      body = "Code: #{String.duplicate("0", 40)}"
      result = Redactor.redact_response_body(body)
      assert result == "Code: <REDACTED>"

      # Mixed alphanumeric
      # 40 chars
      mixed_token = String.duplicate("a1B2c3D4", 5)
      body = "Mixed: #{mixed_token}"
      result = Redactor.redact_response_body(body)
      assert result == "Mixed: <REDACTED>"

      # Token with only alphanumeric (regex only matches [a-zA-Z0-9])
      # 36 chars, all alphanumeric
      alphanumeric_token = String.duplicate("abc123", 6)
      body = "Special: #{alphanumeric_token}"
      result = Redactor.redact_response_body(body)
      assert result == "Special: <REDACTED>"
    end

    test "handles deeply nested JSON structures" do
      # Create deeply nested JSON (10 levels to keep test manageable)
      deeply_nested =
        1..10
        |> Enum.reduce(%{"final" => "value"}, fn i, acc ->
          %{"level#{i}" => %{"secret_key" => "secret#{i}", "data" => acc}}
        end)

      json_string = Jason.encode!(deeply_nested)

      # Should handle redaction without stack overflow
      result = Redactor.redact_response_body(json_string)
      decoded = Jason.decode!(result)

      # Verify secrets are redacted at all levels
      # The structure is level10 -> level9 -> ... -> level1 -> final
      assert get_in(decoded, ["level10", "secret_key"]) == "<REDACTED>"
      assert get_in(decoded, ["level10", "data", "level9", "secret_key"]) == "<REDACTED>"
      # But normal data remains
      assert get_in(decoded, [
               "level10",
               "data",
               "level9",
               "data",
               "level8",
               "data",
               "level7",
               "data",
               "level6",
               "data",
               "level5",
               "data",
               "level4",
               "data",
               "level3",
               "data",
               "level2",
               "data",
               "level1",
               "data",
               "final"
             ]) == "value"
    end

    test "handles large JSON objects efficiently" do
      # Create JSON object with many fields
      many_secrets =
        for i <- 1..1000, into: %{} do
          {"secret_key_#{i}", "secret_value_#{i}"}
        end
        |> Map.put("normal_field", "normal_value")

      json_string = Jason.encode!(many_secrets)

      # Should handle redaction of many fields efficiently
      result = Redactor.redact_response_body(json_string)
      decoded = Jason.decode!(result)

      # Sample check - not all 1000 for test performance
      assert decoded["secret_key_1"] == "<REDACTED>"
      assert decoded["secret_key_500"] == "<REDACTED>"
      assert decoded["normal_field"] == "normal_value"
    end

    test "handles malformed JSON gracefully with various edge cases" do
      malformed_cases = [
        "{invalid json",
        # Missing closing brace
        "{\"key\": \"value\"",
        # Missing value
        "{\"key\": }",
        # Trailing comma
        "{\"key\": \"value\",}",
        # Empty string
        "",
        # Valid JSON but not object
        "null",
        # Array instead of object
        "[]",
        # String instead of object
        "\"just a string\"",
        # Invalid Unicode surrogate
        "{\"key\": \"\\uD800\"}"
      ]

      for malformed <- malformed_cases do
        # Should not crash
        result = Redactor.redact_response_body(malformed)
        assert is_binary(result)
      end
    end

    test "handles pathological regex cases" do
      # String that could cause regex backtracking
      pathological = String.duplicate("bearer ", 1000) <> "actualtoken123"

      # Should complete in reasonable time
      start_time = System.monotonic_time(:millisecond)
      result = Redactor.redact_response_body(pathological)
      end_time = System.monotonic_time(:millisecond)

      # Should complete within 1 second even for pathological input
      assert end_time - start_time < 1000
      assert String.contains?(result, "<REDACTED>")
    end

    test "handles extreme JSON values" do
      edge_values = %{
        "big_int" => 999_999_999_999_999_999,
        "tiny_float" => 1.0e-100,
        "zero" => 0,
        "negative" => -999_999_999,
        "null_value" => nil,
        "boolean_true" => true,
        "boolean_false" => false,
        "empty_string" => "",
        "unicode_string" => "Hello 🌍 世界",
        "secret_key" => "should_be_redacted",
        "control_chars" => "line1\nline2\ttab\r\nwindows"
      }

      json_string = Jason.encode!(edge_values)
      result = Redactor.redact_response_body(json_string)
      decoded = Jason.decode!(result)

      # Values should be preserved except secrets
      assert decoded["big_int"] == 999_999_999_999_999_999
      assert decoded["tiny_float"] == 1.0e-100
      assert decoded["secret_key"] == "<REDACTED>"
      assert decoded["unicode_string"] == "Hello 🌍 世界"
      assert decoded["control_chars"] == "line1\nline2\ttab\r\nwindows"
    end

    test "handles concurrent redaction operations" do
      # Test that redaction is safe under concurrent access
      test_body =
        Jason.encode!(%{
          "secret_key" => "very_secret_value",
          "normal_data" => "public_information",
          "api_token" => "sensitive_token_data"
        })

      # Run multiple redaction operations concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            result = Redactor.redact_response_body(test_body)
            decoded = Jason.decode!(result)
            {i, decoded["secret_key"] == "<REDACTED>" and decoded["api_token"] == "<REDACTED>"}
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed with proper redaction
      assert Enum.all?(results, fn {_i, success} -> success end)
    end
  end
end
