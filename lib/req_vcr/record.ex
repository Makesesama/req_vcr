defmodule ReqVCR.Record do
  @moduledoc """
  Handles recording HTTP requests to cassettes.
  """

  @volatile_headers ~w[date server set-cookie request-id x-request-id x-amzn-trace-id]
  @auth_params ~w[token apikey api_key]

  @doc """
  Records a live HTTP request to a cassette.
  """
  @spec record_request(Plug.Conn.t(), atom(), String.t(), String.t(), String.t(), String.t()) ::
          Plug.Conn.t()
  def record_request(conn, _name, cassette_path, method, url, body) do
    # Forward headers from the original request
    headers = conn.req_headers

    # Make live request (without going through the test stub)
    # Don't raise on HTTP errors so we can record 4xx/5xx responses
    live_response =
      Req.new(headers: headers)
      |> Req.request!(
        method: method |> String.downcase() |> String.to_atom(),
        url: url,
        body: if(body == "", do: nil, else: body),
        raw: true,
        retry: false
      )

    # Normalize and redact response
    normalized_resp = normalize_response(live_response)

    # Build cassette entry
    entry = %{
      req: %{
        method: method,
        url: redact_url(url),
        # Store the headers we forwarded
        headers: Enum.into(headers, %{}),
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
      |> Enum.into(%{})

    %{
      status: response.status,
      headers: headers,
      body_b64: Base.encode64(response.body || "")
    }
  end

  defp redact_url(url) do
    uri = URI.parse(url)

    redacted_query =
      if uri.query do
        uri.query
        |> URI.decode_query()
        |> Enum.map(fn {key, value} ->
          if String.downcase(key) in @auth_params do
            {key, "<REDACTED>"}
          else
            {key, value}
          end
        end)
        |> URI.encode_query()
      else
        nil
      end

    %{uri | query: redacted_query}
    |> URI.to_string()
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
