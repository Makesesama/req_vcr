defmodule Reqord.Replay do
  @moduledoc """
  Handles replaying HTTP requests from cassettes.
  """

  alias Reqord.CassetteEntry

  @doc """
  Replays a response from a cassette entry.
  """
  @spec replay_response(Plug.Conn.t(), CassetteEntry.t()) :: Plug.Conn.t()
  def replay_response(conn, %CassetteEntry{resp: resp}) do
    # Decode body from base64
    body = if resp.body_b64 != "", do: Base.decode64!(resp.body_b64), else: ""

    # Build response
    conn
    |> Plug.Conn.put_status(resp.status)
    |> Reqord.put_resp_headers(resp.headers)
    |> Plug.Conn.resp(resp.status, body)
  end
end
