defmodule Reqord.RedactCassette do
  @moduledoc """
  Macro for applying custom redaction to HTTP requests and responses within a test.

  This module provides a `redact_cassette` macro that allows users to define custom
  redaction functions that are applied to cassette data during recording and replay.

  ## Basic Usage

      defmodule MyApp.APITest do
        use Reqord.Case
        import Reqord.RedactCassette

        test "fetches user data with redacted sensitive info" do
          redact_cassette redactor: :user_data do
            client = Req.new(plug: {Req.Test, MyApp.ReqStub})
            {:ok, response} = Req.get(client, url: "https://api.example.com/users/123")

            assert response.status == 200
            # Email and SSN will be redacted in cassette but preserved in test
            assert response.body["email"] =~ "@"
          end
        end

        # Define redaction function
        defp redactor(:user_data, _context) do
          %{
            response_body: fn body ->
              body
              |> Jason.decode!()
              |> put_in(["email"], "[EMAIL_REDACTED]")
              |> put_in(["ssn"], "[SSN_REDACTED]")
              |> Jason.encode!()
            end,
            request_headers: fn headers ->
              Map.put(headers, "authorization", "[AUTH_REDACTED]")
            end
          }
        end
      end

  ## Named Redactors

  You can also define named redactors in config and reference them:

      # config/test.exs
      config :reqord,
        redactors: %{
          user_api: fn _context ->
            %{
              response_body: &MyApp.Redactors.redact_user_data/1,
              request_headers: &MyApp.Redactors.redact_auth_headers/1
            }
          end,
          financial_api: fn _context ->
            %{
              response_body: &MyApp.Redactors.redact_financial_data/1
            }
          end
        }

      # Then use in tests
      redact_cassette redactor: :user_api do
        # test code
      end

  ## Redaction Function Format

  Redaction functions receive data and return the redacted version:

  - `response_body_json`: `(map) -> map` - Redacts decoded JSON response body
  - `response_body_raw`: `(binary) -> binary` - Redacts raw binary response body
  - `request_headers`: `(map) -> map` - Redacts request headers
  - `response_headers`: `(map) -> map` - Redacts response headers
  - `url`: `(string) -> string` - Redacts URL (including query params)

  Note: For JSON responses, prefer `response_body_json` which automatically handles
  encoding/decoding using the configured JSON library. Use `response_body_raw` for
  non-JSON content or when you need full control over the binary data.

  ## Advanced Usage

      defmodule MyApp.APITest do
        use Reqord.Case
        import Reqord.RedactCassette

        test "complex redaction example" do
          redact_cassette redactor: fn _context ->
            %{
              response_body_json: &redact_nested_secrets/1,
              request_headers: fn headers ->
                headers
                |> Map.put("authorization", "[REDACTED]")
                |> Map.put("x-api-key", "[REDACTED]")
              end,
              url: fn url ->
                URI.parse(url)
                |> Map.update(:query, nil, fn query ->
                  if query do
                    query
                    |> URI.decode_query()
                    |> Map.put("token", "[REDACTED]")
                    |> URI.encode_query()
                  else
                    nil
                  end
                end)
                |> URI.to_string()
              end
            }
          end do
            # test code
          end
        end

        defp redact_nested_secrets(data) when is_map(data) do
          Enum.reduce(data, %{}, fn {key, value}, acc ->
            cond do
              key in ["api_key", "secret", "token"] ->
                Map.put(acc, key, "[REDACTED]")

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

  ## Integration with Reqord.Case

  The macro works seamlessly with existing `Reqord.Case` functionality. It temporarily
  installs redaction hooks that are applied during cassette recording and replay.
  """

  @doc """
  Applies custom redaction within a test block.

  ## Options

  - `:redactor` - The redaction function or named redactor to use
  - `:cassette` - Optional cassette name override (inherits from test context by default)

  ## Examples

      # Using a named redactor from config
      redact_cassette redactor: :user_api do
        # test code
      end

      # Using an inline function
      redact_cassette redactor: fn _context -> %{response_body: &redact_body/1} end do
        # test code
      end

      # With custom cassette name
      redact_cassette redactor: :user_api, cassette: "custom_name" do
        # test code
      end
  """
  defmacro redact_cassette(opts, do: block) do
    quote do
      # Store current redaction state
      previous_redactor = Process.get(:reqord_redactor)

      # Set up redaction for this block
      redactor = unquote(opts)[:redactor]
      cassette_override = unquote(opts)[:cassette]

      # Create context for redactor function
      test_context = %{
        # Will be set at runtime if available
        test: nil,
        module: __MODULE__
      }

      redaction_config = Reqord.RedactCassette.resolve_redactor(redactor, test_context)

      # Install redaction
      Process.put(:reqord_redactor, redaction_config)

      try do
        unquote(block)
      after
        # Restore previous redaction state
        if previous_redactor do
          Process.put(:reqord_redactor, previous_redactor)
        else
          Process.delete(:reqord_redactor)
        end
      end
    end
  end

  @doc false
  def resolve_redactor(redactor, context) when is_function(redactor, 1) do
    redactor.(context)
  end

  def resolve_redactor(redactor_name, context) when is_atom(redactor_name) do
    # Look up named redactor from config
    redactors = Application.get_env(:reqord, :redactors, %{})

    case Map.get(redactors, redactor_name) do
      nil ->
        raise ArgumentError,
              "Named redactor :#{redactor_name} not found. " <>
                "Available redactors: #{inspect(Map.keys(redactors))}"

      redactor_fn when is_function(redactor_fn, 1) ->
        redactor_fn.(context)

      _ ->
        raise ArgumentError,
              "Redactor :#{redactor_name} must be a function that takes a context"
    end
  end

  def resolve_redactor({module, function}, context) when is_atom(module) and is_atom(function) do
    # Support {Module, :function} tuple syntax
    if Code.ensure_loaded?(module) and function_exported?(module, function, 1) do
      apply(module, function, [context])
    else
      raise ArgumentError,
            "Redactor function #{module}.#{function}/1 not found"
    end
  end

  def resolve_redactor(redactor, _context) do
    raise ArgumentError,
          "Invalid redactor: #{inspect(redactor)}. " <>
            "Must be a function, atom, or {module, function} tuple"
  end

  @doc false
  def get_current_redactor do
    Process.get(:reqord_redactor)
  end

  @doc false
  def apply_redaction(cassette_entry) do
    case get_current_redactor() do
      nil ->
        cassette_entry

      redaction_config when is_map(redaction_config) ->
        cassette_entry
        |> apply_request_redaction(redaction_config)
        |> apply_response_redaction(redaction_config)
    end
  end

  defp apply_request_redaction(entry, config) do
    entry =
      if config[:request_body] && entry.req.body_hash != "-" do
        # Note: Request body is hashed, not stored as text, so we can't directly redact it
        # This would need to be handled at the recording level before hashing
        entry
      else
        entry
      end

    entry =
      if config[:request_headers] do
        redacted_headers = config[:request_headers].(entry.req.headers)
        %{entry | req: %{entry.req | headers: redacted_headers}}
      else
        entry
      end

    if config[:url] do
      redacted_url = config[:url].(entry.req.url)
      %{entry | req: %{entry.req | url: redacted_url}}
    else
      entry
    end
  end

  defp apply_response_redaction(entry, config) do
    entry =
      cond do
        config[:response_body_json] ->
          apply_json_body_redaction(entry, config[:response_body_json])

        config[:response_body_raw] ->
          apply_raw_body_redaction(entry, config[:response_body_raw])

        # Legacy support for response_body
        config[:response_body] ->
          apply_raw_body_redaction(entry, config[:response_body])

        true ->
          entry
      end

    if config[:response_headers] do
      redacted_headers = config[:response_headers].(entry.resp.headers)
      %{entry | resp: %{entry.resp | headers: redacted_headers}}
    else
      entry
    end
  end

  defp apply_json_body_redaction(entry, redactor_fn) do
    case get_response_body(entry) do
      {:ok, body} when is_binary(body) ->
        case decode_json_body(body, entry.resp.headers) do
          {:ok, json_data} ->
            redacted_data = redactor_fn.(json_data)
            redacted_body = Reqord.JSON.encode!(redacted_data)
            put_response_body(entry, redacted_body)

          {:error, _} ->
            # Not JSON, skip redaction
            entry
        end

      _ ->
        entry
    end
  end

  defp apply_raw_body_redaction(entry, redactor_fn) do
    case get_response_body(entry) do
      {:ok, body} when is_binary(body) ->
        redacted_body = redactor_fn.(body)
        put_response_body(entry, redacted_body)

      _ ->
        entry
    end
  end

  defp get_response_body(entry) do
    encoding = entry.resp.body_encoding || "base64"

    case encoding do
      encoding when encoding in ["base64", "text"] ->
        decode_base64_body(entry.resp.body_b64)

      _ ->
        {:error, :unsupported_encoding}
    end
  end

  defp decode_base64_body(body_b64) when is_binary(body_b64) and body_b64 != "" do
    case Base.decode64(body_b64) do
      {:ok, body} -> {:ok, body}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_base64_body(_), do: {:ok, ""}

  defp put_response_body(entry, new_body) do
    case entry.resp.body_encoding || "base64" do
      "base64" ->
        %{entry | resp: %{entry.resp | body_b64: Base.encode64(new_body)}}

      "text" ->
        # For text encoding, content is still stored in body_b64
        %{entry | resp: %{entry.resp | body_b64: Base.encode64(new_body)}}

      _ ->
        entry
    end
  end

  defp decode_json_body(body, headers) do
    # Check if content-type indicates JSON
    content_type = get_content_type(headers)

    if json_content_type?(content_type) do
      Reqord.JSON.decode(body)
    else
      {:error, :not_json}
    end
  end

  defp get_content_type(headers) when is_map(headers) do
    # Try different case variations
    headers["content-type"] ||
      headers["Content-Type"] ||
      headers["Content-type"] ||
      ""
  end

  defp json_content_type?(content_type) do
    content_type =~ ~r/application\/json|text\/json/i
  end
end
