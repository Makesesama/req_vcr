defmodule ReqVCR.RedactorTest do
  use ExUnit.Case

  alias ReqVCR.Redactor

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
  end
end
