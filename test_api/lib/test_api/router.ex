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
    case check_auth(conn, []) do
      {:ok, conn} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!([
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"}
          ])
        )

      {:error, conn} ->
        conn
    end
  end

  get "/api/users/:id" do
    case check_auth(conn, []) do
      {:ok, conn} ->
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

      {:error, conn} ->
        conn
    end
  end

  post "/api/users" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        user = Map.merge(conn.body_params, %{"id" => 3})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(user))

      {:error, conn} ->
        conn
    end
  end

  delete "/api/users/:id" do
    case check_auth(conn, []) do
      {:ok, conn} ->
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

      {:error, conn} ->
        conn
    end
  end

  # Binary content endpoints for testing object support
  get "/api/files/image.jpg" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Serve the real JPEG image from test fixtures
        # Path from test_api subdirectory to the main project's test fixtures
        image_path = Path.join([File.cwd!(), "..", "test", "support", "fixtures", "example_image.jpg"])
        absolute_path = Path.expand(image_path)

        case File.read(absolute_path) do
          {:ok, image_data} ->
            conn
            |> put_resp_content_type("image/jpeg")
            |> send_resp(200, image_data)

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(404, Jason.encode!(%{
              error: "Image not found: #{inspect(reason)}",
              path: absolute_path,
              cwd: File.cwd!()
            }))
        end

      {:error, conn} ->
        conn
    end
  end

  get "/api/files/document.pdf" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Generate a small PDF header for testing binary detection
        pdf_header = "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\n"

        conn
        |> put_resp_content_type("application/pdf")
        |> send_resp(200, pdf_header)

      {:error, conn} ->
        conn
    end
  end

  get "/api/files/large-binary" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Generate deterministic large binary content to test external storage
        # Create exactly 2MB of predictable content
        pattern = "REQORD_TEST_DATA"  # 16 bytes
        chunk_size = 16 * 1024  # 16KB chunks
        chunks_needed = div(2_000_000, chunk_size)  # 125 chunks
        remainder = rem(2_000_000, chunk_size)

        base_chunk = String.duplicate(pattern, div(chunk_size, 16))  # Fill 16KB
        large_content = String.duplicate(base_chunk, chunks_needed) <>
                       String.slice(base_chunk, 0, remainder)

        conn
        |> put_resp_content_type("application/octet-stream")
        |> send_resp(200, large_content)

      {:error, conn} ->
        conn
    end
  end

  # Streaming endpoints for testing streaming support
  get "/api/stream/events" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Server-Sent Events stream
        sse_data = """
        data: {"event": "start", "timestamp": 1609459200}

        data: {"event": "message", "content": "Hello World"}

        data: {"event": "end", "timestamp": 1609459260}

        """

        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> send_resp(200, sse_data)

      {:error, conn} ->
        conn
    end
  end

  get "/api/stream/chat" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Simulated LLM streaming response
        chat_stream = """
        data: {"role": "assistant", "content": "Hello! How"}

        data: {"role": "assistant", "content": " can I help"}

        data: {"role": "assistant", "content": " you today?"}

        data: [DONE]

        """

        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")
        |> send_resp(200, chat_stream)

      {:error, conn} ->
        conn
    end
  end

  get "/api/stream/chunked" do
    case check_auth(conn, []) do
      {:ok, conn} ->
        # Chunked transfer encoding simulation (without conflicting headers)
        chunked_data = "chunk1\nchunk2\nchunk3\nchunk4\n"

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, chunked_data)

      {:error, conn} ->
        conn
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
        {:ok, conn}

      [] ->
        conn =
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
          |> halt()

        {:error, conn}

      _ ->
        conn =
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "Invalid token"}))
          |> halt()

        {:error, conn}
    end
  end
end
