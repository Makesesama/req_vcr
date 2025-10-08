defmodule RedactionExample do
  @moduledoc """
  Example demonstrating the redact_cassette macro for automatic data redaction.

  This example shows how to use custom redaction functions to automatically
  redact sensitive data from HTTP requests and responses while keeping the
  original data available in your tests.
  """

  use Reqord.Case
  import Reqord.RedactCassette

  defp default_stub_name, do: RedactionExample.ReqStub

  def run_example do
    IO.puts("=== Reqord Redaction Example ===\n")

    # Example 1: Basic redaction
    IO.puts("1. Basic Response Body Redaction")
    basic_redaction_example()

    # Example 2: Header redaction
    IO.puts("2. Request Header Redaction")
    header_redaction_example()

    # Example 3: Complex nested data redaction
    IO.puts("3. Complex Nested Data Redaction")
    nested_redaction_example()

    # Example 4: Named redactors from config
    IO.puts("4. Named Redactors from Config")
    config_redactor_example()

    IO.puts("\n=== Example Complete ===")
  end

  def basic_redaction_example do
    redact_cassette redactor: &basic_user_redactor/1 do
      client = Req.new(plug: {Req.Test, default_stub_name()})

      # This would normally hit a real API
      {:ok, response} = Req.get(client, url: "https://api.example.com/users/123")

      # In your test, you see the original data
      IO.puts("  Test sees: email = #{response.body["email"]}")
      IO.puts("  Test sees: name = #{response.body["name"]}")

      # But the cassette will have redacted data
      IO.puts("  Cassette stores: email = [REDACTED], name = #{response.body["name"]}")
    end

    IO.puts("")
  end

  def header_redaction_example do
    redact_cassette redactor: &auth_redactor/1 do
      client = Req.new(plug: {Req.Test, default_stub_name()})

      {:ok, _response} =
        Req.get(client,
          url: "https://api.example.com/protected",
          headers: [
            {"authorization", "Bearer secret_token_123"},
            {"x-api-key", "api_key_456"}
          ]
        )

      IO.puts("  Headers redacted in cassette: authorization and x-api-key")
    end

    IO.puts("")
  end

  def nested_redaction_example do
    redact_cassette redactor: &nested_redactor/1 do
      client = Req.new(plug: {Req.Test, default_stub_name()})

      {:ok, response} = Req.get(client, url: "https://api.example.com/users/complex")

      IO.puts("  Complex nested data redaction applied")
      IO.puts("  User profile email: #{get_in(response.body, ["user", "profile", "email"])}")
      IO.puts("  API keys and secrets redacted in cassette")
    end

    IO.puts("")
  end

  def config_redactor_example do
    # Set up named redactor in config
    Application.put_env(:reqord, :redactors, %{
      financial_api: fn _context ->
        %{
          response_body_json: fn json_data ->
            json_data
            |> Map.update("account_number", nil, fn _ -> "[ACCOUNT_REDACTED]" end)
            |> Map.update("ssn", nil, fn _ -> "[SSN_REDACTED]" end)
          end
        }
      end
    })

    redact_cassette redactor: :financial_api do
      client = Req.new(plug: {Req.Test, default_stub_name()})

      {:ok, response} = Req.get(client, url: "https://api.bank.com/account")

      IO.puts("  Using named redactor from config")
      IO.puts("  Financial data redacted: account_number, ssn")
    end

    IO.puts("")
  end

  # Redactor function definitions
  defp basic_user_redactor(_context) do
    %{
      response_body_json: fn json_data ->
        Map.put(json_data, "email", "[REDACTED]")
      end
    }
  end

  defp auth_redactor(_context) do
    %{
      request_headers: fn headers ->
        headers
        |> Map.put("authorization", "[REDACTED]")
        |> Map.put("x-api-key", "[REDACTED]")
      end
    }
  end

  defp nested_redactor(_context) do
    %{
      response_body_json: &redact_nested_data/1
    }
  end

  defp redact_nested_data(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      cond do
        key in ["email", "api_key", "secret", "token", "password"] ->
          Map.put(acc, key, "[#{String.upcase(key)}_REDACTED]")

        is_map(value) ->
          Map.put(acc, key, redact_nested_data(value))

        is_list(value) ->
          Map.put(acc, key, Enum.map(value, &redact_nested_data/1))

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp redact_nested_data(data), do: data
end

# Run the example
# RedactionExample.run_example()
