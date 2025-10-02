defmodule ReqVCR.CassetteEntry do
  @moduledoc """
  Represents a single cassette entry with request and response data.

  This struct provides type safety and validation for cassette entries,
  ensuring consistency across the application.
  """

  @type headers :: %{String.t() => String.t()}

  @type t :: %__MODULE__{
          req: __MODULE__.Request.t(),
          resp: __MODULE__.Response.t()
        }

  defstruct [:req, :resp]

  defmodule Request do
    @moduledoc """
    Represents the request portion of a cassette entry.
    """

    @type t :: %__MODULE__{
            method: String.t(),
            url: String.t(),
            headers: ReqVCR.CassetteEntry.headers(),
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
            headers: ReqVCR.CassetteEntry.headers(),
            body_b64: String.t()
          }

    defstruct [:status, :headers, :body_b64]

    @doc """
    Creates a new Response struct with validation.
    """
    @spec new(pos_integer(), map(), String.t()) :: {:ok, t()} | {:error, String.t()}
    def new(status, headers, body_b64)
        when is_integer(status) and status > 0 and is_binary(body_b64) do
      normalized_headers = normalize_headers(headers)

      response = %__MODULE__{
        status: status,
        headers: normalized_headers,
        body_b64: body_b64
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

      iex> {:ok, req} = ReqVCR.CassetteEntry.Request.new("GET", "https://api.example.com", %{}, "-")
      iex> {:ok, resp} = ReqVCR.CassetteEntry.Response.new(200, %{}, "dGVzdA==")
      iex> ReqVCR.CassetteEntry.new(req, resp)
      {:ok, %ReqVCR.CassetteEntry{...}}
  """
  @spec new(Request.t(), Response.t()) :: {:ok, t()} | {:error, String.t()}
  def new(%Request{} = req, %Response{} = resp) do
    entry = %__MODULE__{
      req: req,
      resp: resp
    }

    {:ok, entry}
  end

  def new(_, _), do: {:error, "Both request and response must be valid structs"}

  @doc """
  Creates a CassetteEntry from raw data with validation.

  This is useful when loading from JSON or creating from HTTP data.
  """
  @spec from_raw(map()) :: {:ok, t()} | {:error, String.t()}
  def from_raw(%{"req" => req_data, "resp" => resp_data}) do
    with {:ok, req} <- create_request_from_raw(req_data),
         {:ok, resp} <- create_response_from_raw(resp_data) do
      new(req, resp)
    end
  end

  def from_raw(_), do: {:error, "Entry must have 'req' and 'resp' fields"}

  @doc """
  Converts a CassetteEntry to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{req: req, resp: resp}) do
    %{
      "req" => %{
        "method" => req.method,
        "url" => req.url,
        "headers" => req.headers,
        "body_hash" => req.body_hash
      },
      "resp" => %{
        "status" => resp.status,
        "headers" => resp.headers,
        "body_b64" => resp.body_b64
      }
    }
  end

  @doc """
  Validates that a CassetteEntry has all required fields and valid data.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{req: %Request{}, resp: %Response{}} = entry) do
    with :ok <- validate_request(entry.req),
         :ok <- validate_response(entry.resp) do
      {:ok, entry}
    end
  end

  def validate(_), do: {:error, "Invalid cassette entry structure"}

  # Private helper functions

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
    Response.new(status, headers, body_b64)
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
end
