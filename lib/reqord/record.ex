defmodule Reqord.Record do
  @moduledoc """
  Handles recording HTTP requests to cassettes.
  """

  alias Reqord.{CassetteEntry, CassetteState, Config, Redactor}

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
    headers = conn.req_headers

    # Make live request and handle the response
    live_response = make_live_request(headers, method, url, body)
    normalized_resp = normalize_response(live_response)

    # Create and store cassette entry
    entry = create_cassette_entry(method, url, headers, body, normalized_resp)
    store_cassette_entry(entry, cassette_path, mode)

    # Return the response
    build_response(conn, live_response, normalized_resp)
  end

  # Private helper functions

  defp make_live_request(headers, method, url, body) do
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
        Logger.debug("Network error while recording request to #{url}: #{inspect(reason)}")
        raise exception

      {:error, exception} ->
        require Logger
        Logger.debug("Request failed while recording to #{url}: #{inspect(exception)}")
        raise exception
    end
  end

  defp create_cassette_entry(method, url, headers, body, normalized_resp) do
    with {:ok, req} <-
           CassetteEntry.Request.new(
             method,
             Redactor.redact_url(url),
             Redactor.redact_headers(headers),
             hash_body(method, body)
           ),
         {:ok, resp} <-
           CassetteEntry.Response.new_with_raw_body(
             normalized_resp[:status],
             normalized_resp[:headers],
             normalized_resp[:raw_body]
           ),
         # Create entry with timestamp
         {:ok, entry} <- CassetteEntry.new(req, resp, System.system_time(:microsecond)) do
      entry
    else
      {:error, reason} ->
        require Logger
        Logger.error("Failed to create cassette entry: #{reason}")
        raise "Cassette entry creation failed: #{reason}"
    end
  end

  defp store_cassette_entry(entry, cassette_path, mode) do
    case mode do
      :all ->
        handle_all_mode_storage(entry, cassette_path)

      _ ->
        # Use async writer for better performance
        entry_map = CassetteEntry.to_map(entry)
        Reqord.CassetteWriter.write_entry(cassette_path, entry_map)
    end
  end

  defp handle_all_mode_storage(entry, cassette_path) do
    # Check if this is the first request by seeing if GenServer state is empty
    current_entries_before = CassetteState.get_entries(cassette_path)
    is_first_request = Enum.empty?(current_entries_before)

    # If this is the first request, clear the existing cassette file
    if is_first_request && File.exists?(cassette_path) do
      storage_backend = Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem)
      storage_backend.delete_cassette(cassette_path)
    end

    CassetteState.append_entry(cassette_path, entry)

    # Use async writer for better performance
    entry_map = CassetteEntry.to_map(entry)
    Reqord.CassetteWriter.write_entry(cassette_path, entry_map)
  end

  defp build_response(conn, live_response, normalized_resp) do
    conn
    |> Plug.Conn.put_status(live_response.status)
    |> Reqord.put_resp_headers(normalized_resp[:headers])
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

    # Keep raw body for smart encoding detection
    raw_body = Redactor.redact_response_body(response.body || "")

    %{
      status: response.status,
      headers: headers,
      raw_body: raw_body,
      # Keep for backward compatibility in case fallback is needed
      body_b64: Base.encode64(raw_body)
    }
  end

  defp hash_body(method, body) do
    if method in ["POST", "PUT", "PATCH"] and body != "" do
      :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    else
      "-"
    end
  end
end
