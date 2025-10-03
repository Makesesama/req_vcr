defmodule Reqord.Record do
  @moduledoc """
  Handles recording HTTP requests to cassettes.
  """

  alias Reqord.{Cassette, CassetteEntry, Config, Redactor}

  @doc """
  Records a live HTTP request to a cassette.
  """
  @spec record_request(Plug.Conn.t(), atom(), String.t(), String.t(), String.t(), String.t()) ::
          Plug.Conn.t()
  def record_request(conn, name, cassette_path, method, url, body) do
    record_request(conn, name, cassette_path, method, url, body, :new_episodes)
  end

  @doc """
  Records a live HTTP request to a cassette with specific mode.
  """
  @spec record_request(
          Plug.Conn.t(),
          atom(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          atom()
        ) ::
          Plug.Conn.t()
  def record_request(conn, _name, cassette_path, method, url, body, mode) do
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

    # Build cassette entry using structs
    with {:ok, req} <-
           CassetteEntry.Request.new(
             method,
             Redactor.redact_url(url),
             Redactor.redact_headers(headers),
             hash_body(method, body)
           ),
         {:ok, resp} <-
           CassetteEntry.Response.new(
             normalized_resp[:status],
             normalized_resp[:headers],
             normalized_resp[:body_b64]
           ),
         {:ok, entry} <- CassetteEntry.new(req, resp) do
      # Handle different record modes
      case mode do
        :all ->
          # In :all mode, always replace the entire cassette (Ruby VCR behavior)
          Cassette.replace(cassette_path, entry)

        :new_episodes ->
          # In :new_episodes mode, always append
          Cassette.append(cassette_path, entry)

        _ ->
          # Default to append for other modes
          Cassette.append(cassette_path, entry)
      end
    else
      {:error, reason} ->
        require Logger
        Logger.error("Failed to create cassette entry: #{reason}")
        raise "Cassette entry creation failed: #{reason}"
    end

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
      |> Enum.reject(fn {key, _} -> String.downcase(key) in Config.volatile_headers() end)
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

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      Plug.Conn.put_resp_header(acc, key, value)
    end)
  end
end
