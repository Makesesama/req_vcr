defmodule Reqord.Replay do
  @moduledoc """
  Handles replaying HTTP requests from cassettes.
  """

  alias Reqord.CassetteEntry

  @doc """
  Replays a response from a cassette entry with support for different body encodings.
  """
  @spec replay_response(Plug.Conn.t(), CassetteEntry.t()) :: Plug.Conn.t()
  def replay_response(conn, %CassetteEntry{resp: resp}) do
    case load_response_body(resp) do
      {:ok, body} ->
        conn
        |> Plug.Conn.put_status(resp.status)
        |> Reqord.put_resp_headers(resp.headers)
        |> Plug.Conn.resp(resp.status, body)

      {:error, reason} ->
        require Logger
        Logger.error("Failed to load response body: #{reason}")

        # Fallback to empty response to avoid crashing
        conn
        |> Plug.Conn.put_status(resp.status)
        |> Reqord.put_resp_headers(resp.headers)
        |> Plug.Conn.resp(resp.status, "")
    end
  end

  @doc """
  Loads the response body based on the encoding type and storage method.
  """
  @spec load_response_body(CassetteEntry.Response.t()) :: {:ok, binary()} | {:error, String.t()}
  def load_response_body(%CassetteEntry.Response{} = resp) do
    # Default for backward compatibility
    encoding = resp.body_encoding || "base64"

    case encoding do
      "base64" ->
        load_base64_body(resp)

      "text" ->
        load_base64_body(resp)

      "binary" ->
        load_base64_body(resp)

      "stream" ->
        load_stream_body(resp)

      "external_" <> _type ->
        load_external_body(resp)

      unknown ->
        {:error, "Unknown body encoding: #{unknown}"}
    end
  end

  # Private helper functions

  defp load_base64_body(%CassetteEntry.Response{body_b64: body_b64}) do
    if body_b64 != "" do
      case Base.decode64(body_b64) do
        {:ok, body} -> {:ok, body}
        :error -> {:error, "Invalid base64 encoding"}
      end
    else
      {:ok, ""}
    end
  rescue
    e -> {:error, "Base64 decoding error: #{Exception.message(e)}"}
  end

  defp load_external_body(%CassetteEntry.Response{body_external_ref: ref}) when is_binary(ref) do
    storage_backend = Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem)

    case storage_backend.load_object(ref) do
      {:ok, content} -> {:ok, content}
      {:error, :not_found} -> {:error, "External object not found: #{ref}"}
      {:error, reason} -> {:error, "Failed to load external object: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "External storage error: #{Exception.message(e)}"}
  end

  defp load_external_body(%CassetteEntry.Response{body_external_ref: nil}) do
    {:error, "External reference is nil"}
  end

  defp load_stream_body(%CassetteEntry.Response{} = resp) do
    if resp.body_external_ref do
      load_external_stream(resp)
    else
      load_base64_body(resp)
    end
  end

  defp load_external_stream(%CassetteEntry.Response{body_external_ref: ref})
       when is_binary(ref) do
    storage_backend = Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem)

    case storage_backend.load_stream(ref) do
      {:ok, chunks} ->
        stream_speed = Application.get_env(:reqord, :stream_speed, 0)

        if stream_speed == 0 do
          body = Enum.map_join(chunks, &extract_chunk_data/1)
          {:ok, body}
        else
          replay_stream_with_timing(chunks, stream_speed)
        end

      {:error, :not_found} ->
        {:error, "External stream not found: #{ref}"}

      {:error, reason} ->
        {:error, "Failed to load external stream: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Stream loading error: #{Exception.message(e)}"}
  end

  defp extract_chunk_data(chunk) when is_map(chunk) do
    Map.get(chunk, "data", "")
  end

  defp extract_chunk_data({_timestamp, data}) when is_binary(data) do
    data
  end

  defp extract_chunk_data(_), do: ""

  defp replay_stream_with_timing(chunks, speed_multiplier) do
    case extract_timestamps_and_data(chunks) do
      [] ->
        {:ok, ""}

      [{_first_timestamp, _first_data} | _] = timed_chunks ->
        parent = self()

        spawn_link(fn ->
          replay_chunks_with_timing(timed_chunks, speed_multiplier, parent)
        end)

        body = Enum.map_join(timed_chunks, fn {_ts, data} -> data end)
        {:ok, body}
    end
  end

  defp extract_timestamps_and_data(chunks) do
    chunks
    |> Enum.map(&extract_timestamp_and_data/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_timestamp_and_data(%{"timestamp" => ts, "data" => data}) when is_number(ts) do
    {ts, data}
  end

  defp extract_timestamp_and_data({timestamp, data}) when is_number(timestamp) do
    {timestamp, data}
  end

  defp extract_timestamp_and_data(_), do: nil

  defp replay_chunks_with_timing([{first_ts, _} | _] = chunks, speed_multiplier, _parent) do
    chunks
    |> Enum.reduce(first_ts, fn {timestamp, _data}, prev_timestamp ->
      delay_ms = max(0, round((timestamp - prev_timestamp) / speed_multiplier))

      if delay_ms > 0 do
        Process.sleep(delay_ms)
      end

      timestamp
    end)
  end
end
