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
        # Text is still stored as base64
        load_base64_body(resp)

      "binary" ->
        # Inline binary is still stored as base64
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
    # For basic stream support, check if we have external stream data
    if resp.body_external_ref do
      load_external_stream(resp)
    else
      # Fallback to inline base64 for simple streams
      load_base64_body(resp)
    end
  end

  defp load_external_stream(%CassetteEntry.Response{body_external_ref: ref})
       when is_binary(ref) do
    storage_backend = Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem)

    case storage_backend.load_stream(ref) do
      {:ok, chunks} ->
        # For instant replay, concatenate all chunks
        # Future enhancement: replay with timing
        # 0 = instant
        stream_speed = Application.get_env(:reqord, :stream_speed, 0)

        if stream_speed == 0 do
          body = chunks |> Enum.map(&extract_chunk_data/1) |> Enum.join()
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

  # Future enhancement: timing-accurate stream replay
  defp replay_stream_with_timing(chunks, _speed_multiplier) do
    # For now, just return concatenated chunks
    # TODO: Implement actual timing-based replay using GenServer or Task
    body = chunks |> Enum.map(&extract_chunk_data/1) |> Enum.join()
    {:ok, body}
  end
end
