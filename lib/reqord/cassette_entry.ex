defmodule Reqord.CassetteEntry do
  @moduledoc """
  Represents a single cassette entry with request, response, and timestamp data.

  This struct provides type safety and validation for cassette entries,
  ensuring consistency across the application. All entries now
  include microsecond-precision timestamps for chronological ordering.

  ## Structure

  A CassetteEntry contains:
  - `req`: The HTTP request details (method, URL, headers, body hash)
  - `resp`: The HTTP response details (status, headers, base64-encoded body)
  - `recorded_at`: Microsecond timestamp when the request was initiated

  ## Timestamp Ordering

  The `recorded_at` field enables chronological replay even when concurrent
  requests complete out of order:

      # Concurrent requests might complete as: POST(t=200), DELETE(t=100)
      # But will be replayed as: DELETE(t=100), POST(t=200)

  This solves ID mismatch errors in concurrent testing scenarios where
  resource creation and deletion happen in parallel.

  ## JSON Format

  When serialized to cassette files, entries have this format:

      {
        "req": {
          "method": "POST",
          "url": "https://api.example.com/users",
          "headers": {"authorization": "<REDACTED>"},
          "body_hash": "abc123..."
        },
        "resp": {
          "status": 201,
          "headers": {"content-type": "application/json"},
          "body_b64": "eyJpZCI6MSwidXNlciI6IkFsaWNlIn0="
        },
        "recorded_at": 1759657159025077
      }
  """

  @type headers :: %{String.t() => String.t()}

  @type t :: %__MODULE__{
          req: __MODULE__.Request.t(),
          resp: __MODULE__.Response.t(),
          recorded_at: integer() | nil
        }

  defstruct [:req, :resp, :recorded_at]

  defmodule Request do
    @moduledoc """
    Represents the request portion of a cassette entry.
    """

    @type t :: %__MODULE__{
            method: String.t(),
            url: String.t(),
            headers: Reqord.CassetteEntry.headers(),
            body_hash: String.t()
          }

    defstruct [:method, :url, :headers, :body_hash]

    @doc """
    Creates a new Request struct with validation.
    """
    @spec new(String.t(), String.t(), map(), String.t()) :: {:ok, t()} | {:error, String.t()}
    def new(method, url, headers, body_hash) when is_binary(method) and is_binary(url) do
      normalized_headers = normalize_headers(headers)

      request = %__MODULE__{
        method: String.upcase(method),
        url: url,
        headers: normalized_headers,
        body_hash: body_hash
      }

      {:ok, request}
    rescue
      e ->
        {:error, "Invalid request data: #{Exception.message(e)}"}
    end

    def new(_, _, _, _), do: {:error, "Method and URL must be strings"}

    # Normalize headers to ensure consistent format
    defp normalize_headers(headers) when is_map(headers) do
      headers
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})
    end

    defp normalize_headers(headers) when is_list(headers) do
      headers
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})
    end

    defp normalize_headers(_), do: %{}
  end

  defmodule Response do
    @moduledoc """
    Represents the response portion of a cassette entry.
    """

    @type t :: %__MODULE__{
            status: pos_integer(),
            headers: Reqord.CassetteEntry.headers(),
            body_b64: String.t(),
            body_encoding: String.t(),
            body_external_ref: String.t() | nil,
            stream_metadata: map() | nil
          }

    defstruct [:status, :headers, :body_b64, :body_encoding, :body_external_ref, :stream_metadata]

    @doc """
    Creates a new Response struct with validation.

    For backward compatibility, accepts Base64-encoded body.
    Use `new_with_raw_body/3` for automatic encoding detection.
    """
    @spec new(pos_integer(), map(), String.t()) :: {:ok, t()} | {:error, String.t()}
    def new(status, headers, body_b64)
        when is_integer(status) and status > 0 and is_binary(body_b64) do
      normalized_headers = normalize_headers(headers)

      response = %__MODULE__{
        status: status,
        headers: normalized_headers,
        body_b64: body_b64,
        # Legacy default
        body_encoding: "base64",
        body_external_ref: nil,
        stream_metadata: nil
      }

      {:ok, response}
    rescue
      e ->
        {:error, "Invalid response data: #{Exception.message(e)}"}
    end

    def new(status, _, _) when not is_integer(status) or status <= 0 do
      {:error, "Status must be a positive integer"}
    end

    def new(_, _, body) when not is_binary(body) do
      {:error, "Body must be a base64-encoded string"}
    end

    @doc """
    Creates a new Response struct with automatic encoding detection.

    This function analyzes the raw body content and determines the optimal
    storage strategy based on content type and size.
    """
    @spec new_with_raw_body(pos_integer(), map(), binary()) :: {:ok, t()} | {:error, String.t()}
    def new_with_raw_body(status, headers, raw_body)
        when is_integer(status) and status > 0 and is_binary(raw_body) do
      normalized_headers = normalize_headers(headers)
      content_type = Reqord.ContentAnalyzer.extract_content_type(normalized_headers)

      {encoding_type, content} = Reqord.ContentAnalyzer.analyze_content(content_type, raw_body)
      body_size = byte_size(raw_body)

      cond do
        encoding_type == :stream ->
          create_stream_response(status, normalized_headers, content)

        Reqord.ContentAnalyzer.should_store_externally?(encoding_type, body_size) ->
          create_external_response(status, normalized_headers, content, encoding_type)

        true ->
          create_inline_response(status, normalized_headers, content, encoding_type)
      end
    rescue
      e ->
        {:error, "Invalid response data: #{Exception.message(e)}"}
    end

    # Helper functions for creating different response types

    defp create_inline_response(status, headers, content, encoding_type) do
      response = %__MODULE__{
        status: status,
        headers: headers,
        body_b64: Base.encode64(content),
        body_encoding: to_string(encoding_type),
        body_external_ref: nil,
        stream_metadata: nil
      }

      {:ok, response}
    end

    defp create_external_response(status, headers, content, encoding_type) do
      # Generate content hash for external storage
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      # Store the content externally (implementation will be added to storage backend)
      storage_backend = Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem)

      case storage_backend.store_object(content_hash, content) do
        {:ok, _} ->
          response = %__MODULE__{
            status: status,
            headers: headers,
            # Empty for external storage
            body_b64: "",
            body_encoding: "external_#{encoding_type}",
            body_external_ref: content_hash,
            stream_metadata: %{"size" => byte_size(content)}
          }

          {:ok, response}

        {:error, _reason} ->
          # Fallback to inline storage if external fails
          create_inline_response(status, headers, content, encoding_type)
      end
    end

    defp create_stream_response(status, headers, content) do
      # For now, store streams inline with metadata
      # Future enhancement: parse SSE/chunked streams
      stream_metadata = %{
        "type" => "stream",
        "size" => byte_size(content),
        "detected_at" => DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      }

      response = %__MODULE__{
        status: status,
        headers: headers,
        body_b64: Base.encode64(content),
        body_encoding: "stream",
        body_external_ref: nil,
        stream_metadata: stream_metadata
      }

      {:ok, response}
    end

    # Normalize headers to ensure consistent format
    defp normalize_headers(headers) when is_map(headers) do
      headers
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})
    end

    defp normalize_headers(headers) when is_list(headers) do
      headers
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})
    end

    defp normalize_headers(_), do: %{}
  end

  @doc """
  Creates a new CassetteEntry struct with validation.

  ## Examples

      iex> {:ok, req} = Reqord.CassetteEntry.Request.new("GET", "https://api.example.com", %{}, "-")
      iex> {:ok, resp} = Reqord.CassetteEntry.Response.new(200, %{}, "dGVzdA==")
      iex> Reqord.CassetteEntry.new(req, resp)
      {:ok, %Reqord.CassetteEntry{...}}
  """
  @spec new(Request.t(), Response.t(), integer() | nil) :: {:ok, t()} | {:error, String.t()}
  def new(req, resp, recorded_at \\ nil)

  def new(%Request{} = req, %Response{} = resp, recorded_at) do
    # Always use timestamp - either provided or current time
    timestamp = recorded_at || System.system_time(:microsecond)

    entry = %__MODULE__{
      req: req,
      resp: resp,
      recorded_at: timestamp
    }

    {:ok, entry}
  end

  def new(_, _, _), do: {:error, "Both request and response must be valid structs"}

  @doc """
  Creates a CassetteEntry from raw data with validation.

  This is useful when loading from JSON or creating from HTTP data.
  """
  @spec from_raw(map()) :: {:ok, t()} | {:error, String.t()}
  def from_raw(%{"req" => req_data, "resp" => resp_data} = data) do
    with {:ok, req} <- create_request_from_raw(req_data),
         {:ok, resp} <- create_response_from_raw(resp_data) do
      # Support backward compatibility - use nil if timestamp not present
      recorded_at = Map.get(data, "recorded_at")
      new(req, resp, recorded_at)
    end
  end

  def from_raw(_), do: {:error, "Entry must have 'req' and 'resp' fields"}

  @doc """
  Converts a CassetteEntry to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{req: req, resp: resp, recorded_at: recorded_at}) do
    %{
      "req" => %{
        "method" => req.method,
        "url" => req.url,
        "headers" => req.headers,
        "body_hash" => req.body_hash
      },
      "resp" => resp_to_map(resp),
      "recorded_at" => recorded_at
    }
  end

  @doc """
  Validates that a CassetteEntry has all required fields and valid data.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{req: %Request{}, resp: %Response{}} = entry) do
    with :ok <- validate_request(entry.req),
         :ok <- validate_response(entry.resp),
         :ok <- validate_timestamp(entry.recorded_at) do
      {:ok, entry}
    end
  end

  def validate(_), do: {:error, "Invalid cassette entry structure"}

  # Private helper functions

  defp resp_to_map(resp) do
    base = %{
      "status" => resp.status,
      "headers" => resp.headers,
      "body_b64" => resp.body_b64
    }

    # Add new fields if they exist
    base
    |> maybe_add_field("body_encoding", resp.body_encoding)
    |> maybe_add_field("body_external_ref", resp.body_external_ref)
    |> maybe_add_field("stream_metadata", resp.stream_metadata)
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp create_request_from_raw(%{
         "method" => method,
         "url" => url,
         "headers" => headers,
         "body_hash" => body_hash
       }) do
    Request.new(method, url, headers, body_hash)
  end

  defp create_request_from_raw(data) do
    required = ["method", "url", "body_hash"]
    missing = required -- Map.keys(data)

    if missing == [] do
      headers = Map.get(data, "headers", %{})
      Request.new(data["method"], data["url"], headers, data["body_hash"])
    else
      {:error, "Missing required request fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp create_response_from_raw(%{"status" => status} = data) do
    headers = Map.get(data, "headers", %{})
    body_b64 = Map.get(data, "body_b64", "")

    # Create basic response
    case Response.new(status, headers, body_b64) do
      {:ok, response} ->
        # Add new fields if present
        enhanced_response = %{
          response
          | body_encoding: Map.get(data, "body_encoding", "base64"),
            body_external_ref: Map.get(data, "body_external_ref"),
            stream_metadata: Map.get(data, "stream_metadata")
        }

        {:ok, enhanced_response}

      error ->
        error
    end
  end

  defp create_response_from_raw(_) do
    {:error, "Missing required response field: status"}
  end

  defp validate_request(%Request{method: method, url: url, body_hash: body_hash})
       when is_binary(method) and is_binary(url) and is_binary(body_hash) do
    if method in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"] do
      :ok
    else
      {:error, "Invalid HTTP method: #{method}"}
    end
  end

  defp validate_request(_), do: {:error, "Invalid request structure"}

  defp validate_response(%Response{status: status, body_b64: body_b64})
       when is_integer(status) and status > 0 and is_binary(body_b64) do
    if status >= 100 and status < 600 do
      case Base.decode64(body_b64) do
        {:ok, _} -> :ok
        :error -> {:error, "Invalid base64 encoding in response body"}
      end
    else
      {:error, "Invalid HTTP status code: #{status}"}
    end
  end

  defp validate_response(_), do: {:error, "Invalid response structure"}

  defp validate_timestamp(timestamp) when is_integer(timestamp) and timestamp > 0, do: :ok
  defp validate_timestamp(_), do: {:error, "Invalid or missing timestamp"}
end
