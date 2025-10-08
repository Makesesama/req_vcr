defmodule Reqord.RedactCassetteTest do
  use Reqord.Case
  import Reqord.RedactCassette
  alias Reqord.TestHelpers

  @moduletag :example_api

  defp default_stub_name, do: Reqord.ExampleAPIStub

  describe "redact_cassette macro" do
    @tag vcr: "redaction/user_api_basic"
    test "applies custom redaction to response body", _context do
      redact_cassette redactor: &user_data_redactor/1 do
        client = TestHelpers.test_api_client()

        {:ok, response} = Req.get(client, url: "/api/users/1")

        assert response.status == 200
        # With redaction active, we see the redacted data even in tests
        assert response.body["email"] == "[EMAIL_REDACTED]"
        # not redacted
        assert response.body["name"] == "Alice"
      end

      # Note: In :new_episodes mode, cassette verification should be done
      # in a separate test run after the cassette is recorded
    end

    @tag vcr: "redaction/user_api_headers"
    test "applies custom redaction to request headers", _context do
      redact_cassette redactor: &auth_header_redactor/1 do
        client = TestHelpers.test_api_client()

        {:ok, response} =
          Req.get(client,
            url: "/api/users/1",
            # authorization already set by test_api_client
            headers: [{"x-api-key", "key456"}]
          )

        assert response.status == 200
      end
    end

    @tag vcr: "redaction/user_api_url"
    test "applies custom redaction to URLs", _context do
      redact_cassette redactor: &url_redactor/1 do
        client = TestHelpers.test_api_client()

        {:ok, response} =
          Req.get(client,
            url: "/api/users/1?token=secret123&name=alice"
          )

        assert response.status == 200
      end
    end

    @tag vcr: "redaction/complex_nested"
    test "handles complex nested JSON redaction", _context do
      redact_cassette redactor: &nested_data_redactor/1 do
        client = TestHelpers.test_api_client()

        {:ok, response} = Req.get(client, url: "/api/users/1")

        assert response.status == 200
        # With redaction active, we see the redacted data
        assert response.body["email"] == "[EMAIL_REDACTED]"
        # not redacted
        assert response.body["name"] == "Alice"
      end
    end

    @tag vcr: "redaction/named_redactor"
    test "supports named redactors from config", _context do
      # This test would require config setup, testing the pattern
      Application.put_env(:reqord, :redactors, %{
        test_redactor: fn _context ->
          %{
            response_body_json: fn json_data ->
              Map.put(json_data, "email", "[REDACTED_BY_CONFIG]")
            end
          }
        end
      })

      redact_cassette redactor: :test_redactor do
        client = TestHelpers.test_api_client()

        {:ok, response} = Req.get(client, url: "/api/users/1")

        assert response.status == 200
        assert response.body["email"] == "[REDACTED_BY_CONFIG]"
      end
    end

    @tag vcr: "redaction/inline_function"
    test "supports inline redactor functions", _context do
      redact_cassette redactor: fn _context ->
                        %{
                          response_body_json: fn json_data ->
                            Map.put(json_data, "name", "[INLINE_REDACTED]")
                          end
                        }
                      end do
        client = TestHelpers.test_api_client()

        {:ok, response} = Req.get(client, url: "/api/users/1")

        assert response.status == 200
        assert response.body["name"] == "[INLINE_REDACTED]"
      end
    end
  end

  # Redactor functions
  defp user_data_redactor(_context) do
    %{
      response_body_json: fn json_data ->
        Map.put(json_data, "email", "[EMAIL_REDACTED]")
      end
    }
  end

  defp auth_header_redactor(_context) do
    %{
      request_headers: fn headers ->
        headers
        |> Map.put("authorization", "[AUTH_REDACTED]")
        |> Map.put("x-api-key", "[API_KEY_REDACTED]")
      end
    }
  end

  defp url_redactor(_context) do
    %{
      url: fn url ->
        URI.parse(url)
        |> Map.update(:query, nil, fn query ->
          if query do
            query
            |> URI.decode_query()
            |> Map.put("token", "SECRET_REDACTED")
            |> URI.encode_query()
          else
            nil
          end
        end)
        |> URI.to_string()
      end
    }
  end

  defp nested_data_redactor(_context) do
    %{
      response_body_json: &redact_nested_secrets/1
    }
  end

  defp redact_nested_secrets(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      cond do
        key in ["email", "api_key", "secret", "token"] ->
          redacted_value =
            case key do
              "email" -> "[EMAIL_REDACTED]"
              "api_key" -> "[API_KEY_REDACTED]"
              "secret" -> "[SECRET_REDACTED]"
              "token" -> "[TOKEN_REDACTED]"
            end

          Map.put(acc, key, redacted_value)

        is_map(value) ->
          Map.put(acc, key, redact_nested_secrets(value))

        is_list(value) ->
          Map.put(acc, key, Enum.map(value, &redact_nested_secrets/1))

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp redact_nested_secrets(data), do: data
end
