defmodule ReqVCR.Record do
  @moduledoc """
  Handles recording HTTP requests to cassettes.
  """

  alias ReqVCR.Redactor

  @volatile_headers ~w[date server set-cookie request-id x-request-id x-amzn-trace-id]

  @doc """
  Records a live HTTP request to a cassette.
  """
  @spec record_request(Plug.Conn.t(), atom(), String.t(), String.t(), String.t(), String.t()) ::
          Plug.Conn.t()
  def record_request(conn, _name, cassette_path, method, url, body) do
    # Forward headers from the original request
    headers = conn.req_headers

    # Make live request (without going through the test stub)
    # Handle network failures gracefully while allowing 4xx/5xx responses to be recorded
    live_response =
      case Req.new(headers: headers)
           |> Req.request(
             method: method |> String.downcase() |> String.to_atom(),
             url: url,
             body: if(body == "", do: nil, else: body),
             raw: true,
             retry: false
           ) do
        {:ok, response} ->
          response

        {:error, %Req.TransportError{reason: reason} = exception} ->
          require Logger
          Logger.error("Network error while recording request to #{url}: #{inspect(reason)}")
          raise exception

        {:error, exception} ->
          require Logger
          Logger.error("Request failed while recording to #{url}: #{inspect(exception)}")
          raise exception
      end

    # Normalize and redact response
    normalized_resp = normalize_response(live_response)

    # Build cassette entry
    entry = %{
      req: %{
        method: method,
        url: Redactor.redact_url(url),
        headers: Redactor.redact_headers(headers),
        body_hash: hash_body(method, body)
      },
      resp: normalized_resp
    }

    # Append to cassette
    append_to_cassette(cassette_path, entry)

    # Return the response
    conn
    |> Plug.Conn.put_status(live_response.status)
    |> put_headers(normalized_resp[:headers])
    |> Plug.Conn.resp(live_response.status, live_response.body || "")
  end

  defp normalize_response(response) do
    # Filter out volatile headers and convert to string values
    headers =
      response.headers
      |> Enum.reject(fn {key, _} -> String.downcase(key) in @volatile_headers end)
      |> Enum.map(fn {key, value} ->
        # Convert list values to comma-separated string
        string_value =
          case value do
            list when is_list(list) -> Enum.join(list, ", ")
            val -> to_string(val)
          end

        {key, string_value}
      end)
      |> Redactor.redact_headers()

    %{
      status: response.status,
      headers: headers,
      body_b64: Base.encode64(Redactor.redact_response_body(response.body || ""))
    }
  end

  defp hash_body(method, body) do
    if method in ["POST", "PUT", "PATCH"] and body != "" do
      :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    else
      "-"
    end
  end

  defp append_to_cassette(path, entry) do
    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Append entry
    File.write!(path, Jason.encode!(entry) <> "\n", [:append])
  end

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      Plug.Conn.put_resp_header(acc, key, value)
    end)
  end
end
