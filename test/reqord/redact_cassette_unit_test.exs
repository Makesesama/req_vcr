defmodule Reqord.RedactCassetteUnitTest do
  use ExUnit.Case
  import Reqord.RedactCassette

  alias Reqord.{CassetteEntry}

  describe "redact_cassette functionality" do
    test "resolve_redactor with inline function" do
      redactor_fn = fn _context ->
        %{
          response_body_json: fn json_data ->
            Map.put(json_data, "email", "[REDACTED]")
          end
        }
      end

      context = %{test: "test_name", module: MyTestModule}
      config = resolve_redactor(redactor_fn, context)

      assert is_map(config)
      assert is_function(config[:response_body_json])
    end

    test "resolve_redactor with named redactor from config" do
      # Set up config
      Application.put_env(:reqord, :redactors, %{
        test_redactor: fn _context ->
          %{
            response_body_json: fn json_data ->
              Map.put(json_data, "api_key", "[REDACTED]")
            end
          }
        end
      })

      context = %{test: "test_name", module: MyTestModule}
      config = resolve_redactor(:test_redactor, context)

      assert is_map(config)
      assert is_function(config[:response_body_json])

      # Test the function works
      result = config[:response_body_json].(%{"api_key" => "secret123", "data" => "value"})
      assert result["api_key"] == "[REDACTED]"
      assert result["data"] == "value"

      # Clean up
      Application.delete_env(:reqord, :redactors)
    end

    test "apply_redaction with JSON response body" do
      # Create a mock cassette entry
      {:ok, req} = CassetteEntry.Request.new("GET", "http://example.com", %{}, "-")

      {:ok, resp} =
        CassetteEntry.Response.new_with_raw_body(
          200,
          %{"content-type" => "application/json"},
          ~s({"email":"user@example.com","name":"John"})
        )

      {:ok, entry} = CassetteEntry.new(req, resp, System.system_time(:microsecond))

      # Set up redaction config
      redaction_config = %{
        response_body_json: fn json_data ->
          Map.put(json_data, "email", "[EMAIL_REDACTED]")
        end
      }

      # Apply redaction
      Process.put(:reqord_redactor, redaction_config)
      redacted_entry = apply_redaction(entry)
      Process.delete(:reqord_redactor)

      # Verify redaction was applied
      assert redacted_entry != entry

      # Decode the redacted response body
      {:ok, redacted_body} = Base.decode64(redacted_entry.resp.body_b64)
      {:ok, redacted_json} = Reqord.JSON.decode(redacted_body)

      assert redacted_json["email"] == "[EMAIL_REDACTED]"
      assert redacted_json["name"] == "John"
    end

    test "apply_redaction with non-JSON response body (raw)" do
      # Create a mock cassette entry with plain text
      {:ok, req} = CassetteEntry.Request.new("GET", "http://example.com", %{}, "-")

      {:ok, resp} =
        CassetteEntry.Response.new_with_raw_body(
          200,
          %{"content-type" => "text/plain"},
          "This contains sensitive_data that should be redacted"
        )

      {:ok, entry} = CassetteEntry.new(req, resp, System.system_time(:microsecond))

      # Set up redaction config
      redaction_config = %{
        response_body_raw: fn body ->
          String.replace(body, "sensitive_data", "[REDACTED]")
        end
      }

      # Apply redaction
      Process.put(:reqord_redactor, redaction_config)
      redacted_entry = apply_redaction(entry)
      Process.delete(:reqord_redactor)

      # Verify redaction was applied
      {:ok, redacted_body} = Base.decode64(redacted_entry.resp.body_b64)
      assert redacted_body =~ "[REDACTED]"
      assert not (redacted_body =~ "sensitive_data")
    end

    test "apply_redaction with request headers" do
      # Create a mock cassette entry
      {:ok, req} =
        CassetteEntry.Request.new(
          "GET",
          "http://example.com",
          %{"authorization" => "Bearer secret123", "content-type" => "application/json"},
          "-"
        )

      {:ok, resp} = CassetteEntry.Response.new_with_raw_body(200, %{}, "")
      {:ok, entry} = CassetteEntry.new(req, resp, System.system_time(:microsecond))

      # Set up redaction config
      redaction_config = %{
        request_headers: fn headers ->
          Map.put(headers, "authorization", "[AUTH_REDACTED]")
        end
      }

      # Apply redaction
      Process.put(:reqord_redactor, redaction_config)
      redacted_entry = apply_redaction(entry)
      Process.delete(:reqord_redactor)

      # Verify redaction was applied
      assert redacted_entry.req.headers["authorization"] == "[AUTH_REDACTED]"
      assert redacted_entry.req.headers["content-type"] == "application/json"
    end

    test "apply_redaction with URL redaction" do
      # Create a mock cassette entry
      {:ok, req} =
        CassetteEntry.Request.new(
          "GET",
          "http://example.com/api?token=secret123&user=john",
          %{},
          "-"
        )

      {:ok, resp} = CassetteEntry.Response.new_with_raw_body(200, %{}, "")
      {:ok, entry} = CassetteEntry.new(req, resp, System.system_time(:microsecond))

      # Set up redaction config
      redaction_config = %{
        url: fn url ->
          URI.parse(url)
          |> Map.update(:query, nil, fn query ->
            if query do
              query
              |> URI.decode_query()
              |> Map.put("token", "[TOKEN_REDACTED]")
              |> URI.encode_query()
            else
              nil
            end
          end)
          |> URI.to_string()
        end
      }

      # Apply redaction
      Process.put(:reqord_redactor, redaction_config)
      redacted_entry = apply_redaction(entry)
      Process.delete(:reqord_redactor)

      # Verify redaction was applied
      assert redacted_entry.req.url =~ "token=%5BTOKEN_REDACTED%5D"
      assert redacted_entry.req.url =~ "user=john"
    end

    test "no redaction when no redactor is set" do
      # Create a mock cassette entry
      {:ok, req} = CassetteEntry.Request.new("GET", "http://example.com", %{}, "-")
      {:ok, resp} = CassetteEntry.Response.new_with_raw_body(200, %{}, "test body")
      {:ok, entry} = CassetteEntry.new(req, resp, System.system_time(:microsecond))

      # Apply redaction without setting a redactor
      redacted_entry = apply_redaction(entry)

      # Verify no changes were made
      assert redacted_entry == entry
    end
  end
end
