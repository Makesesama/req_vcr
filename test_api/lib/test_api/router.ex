defmodule TestApi.Router do
  @moduledoc """
  Simple API router for testing Reqord.
  """

  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Note: check_auth is now called inside each route handler below

  get "/api/users" do
    with conn <- check_auth(conn, []) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!([
          %{id: 1, name: "Alice", email: "alice@example.com"},
          %{id: 2, name: "Bob", email: "bob@example.com"}
        ])
      )
    end
  end

  get "/api/users/:id" do
    with conn <- check_auth(conn, []) do
      user =
        case id do
          "1" -> %{id: 1, name: "Alice", email: "alice@example.com"}
          "2" -> %{id: 2, name: "Bob", email: "bob@example.com"}
          _ -> nil
        end

      if user do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(user))
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "User not found"}))
      end
    end
  end

  post "/api/users" do
    with conn <- check_auth(conn, []) do
      user = Map.merge(conn.body_params, %{"id" => 3})

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(user))
    end
  end

  delete "/api/users/:id" do
    with conn <- check_auth(conn, []) do
      case id do
        "1" ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{message: "User 1 deleted"}))

        "2" ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{message: "User 2 deleted"}))

        "3" ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{message: "User 3 deleted"}))

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "User not found"}))
      end
    end
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Check authentication header
  defp check_auth(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer test-token"] ->
        conn

      [] ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
        |> halt()

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid token"}))
        |> halt()
    end
  end
end
