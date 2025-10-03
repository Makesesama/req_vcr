defmodule Reqord do
  @moduledoc """
  VCR-style record/replay for HTTP when using `Req`, integrating with `Req.Test`.

  Reqord allows you to record HTTP interactions to cassette files and replay them
  in your tests without requiring any application code changes.

  ## Installation

  Add `reqord` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:req, "~> 0.5"},
          {:reqord, "~> 0.1.0"}
        ]
      end

  ## Quick Start

  ### 1. Configure Req to use Req.Test in your test environment

  In `config/test.exs`:

      config :my_app,
        req_options: [plug: {Req.Test, MyApp.ReqStub}]

  ### 2. Use Reqord.Case in your tests

      defmodule MyApp.APITest do
        use Reqord.Case

        # Specify your Req.Test stub name
        defp default_stub_name, do: MyApp.ReqStub

        test "fetches user data" do
          client = Req.new(Application.get_env(:my_app, :req_options, []))
          {:ok, response} = Req.get(client, url: "https://api.example.com/users/123")

          assert response.status == 200
          assert response.body["name"] == "John Doe"
        end
      end

  ### 3. Record cassettes on first run

      # Record mode - hits live API and saves responses
      REQORD=record API_TOKEN=xxx mix test

      # Subsequent runs use replay mode (default) - no network calls
      mix test

  ## Modes

  Control the VCR mode via the `REQORD` environment variable:

  - `:replay` (default) - Only replay from cassettes, raise on misses
  - `:record` - Always forward to live network and record
  - `:auto` - Replay if match found, otherwise record via live proxy

  ## Examples

  ### Basic Usage with Reqord.Case

      defmodule MyApp.WeatherAPITest do
        use Reqord.Case

        defp default_stub_name, do: MyApp.ReqStub

        # Creates cassette: test/support/cassettes/WeatherAPI/fetches_forecast.jsonl
        test "fetches forecast" do
          client = Req.new(plug: {Req.Test, MyApp.ReqStub})
          {:ok, response} = Req.get(client, url: "https://api.weather.com/forecast")

          assert response.status == 200
          assert is_list(response.body["forecast"])
        end

        # Custom cassette name
        @tag vcr: "weather/special_forecast"
        test "with custom cassette" do
          client = Req.new(plug: {Req.Test, MyApp.ReqStub})
          {:ok, response} = Req.get(client, url: "https://api.weather.com/special")

          assert response.status == 200
        end
      end

  ### Manual Installation

  For more control, you can install Reqord manually:

      defmodule MyApp.CustomTest do
        use ExUnit.Case

        setup do
          Req.Test.set_req_test_to_private()
          Req.Test.set_req_test_from_context(%{async: true})

          Reqord.install!(
            name: MyApp.ReqStub,
            cassette: "my_custom_cassette",
            mode: :replay
          )

          :ok
        end

        test "custom setup" do
          client = Req.new(plug: {Req.Test, MyApp.ReqStub})
          {:ok, response} = Req.get(client, url: "https://api.example.com/data")
          assert response.status == 200
        end
      end

  ### Working with Spawned Processes

  If your test spawns processes that make HTTP requests:

      test "with spawned task" do
        client = Req.new(plug: {Req.Test, MyApp.ReqStub})

        task = Task.async(fn ->
          Req.get(client, url: "https://api.example.com/data")
        end)

        # Allow the task's process to use the stub
        Reqord.allow(MyApp.ReqStub, self(), task.pid)

        {:ok, response} = Task.await(task)
        assert response.status == 200
      end

  ### POST/PUT/PATCH Requests

  Reqord distinguishes requests with different bodies:

      test "creates users" do
        client = Req.new(plug: {Req.Test, MyApp.ReqStub})

        # These will create separate cassette entries
        {:ok, resp1} = Req.post(client,
          url: "https://api.example.com/users",
          json: %{name: "Alice"}
        )

        {:ok, resp2} = Req.post(client,
          url: "https://api.example.com/users",
          json: %{name: "Bob"}
        )

        assert resp1.body["name"] == "Alice"
        assert resp2.body["name"] == "Bob"
      end

  ## How It Works

  ### Request Matching

  Reqord matches requests using a deterministic key:

      METHOD NORMALIZED_URL BODY_HASH

  - **Method**: HTTP method (GET, POST, etc.)
  - **Normalized URL**: Query parameters sorted, auth params removed
  - **Body Hash**: SHA-256 hash for POST/PUT/PATCH, `-` for others

  ### Automatic Redaction

  Sensitive data is automatically redacted:

  **Headers** (set to `<REDACTED>`):
  - `authorization`

  **Query parameters** (set to `<REDACTED>`):
  - `token`, `apikey`, `api_key`

  **Volatile response headers** (removed):
  - `date`, `server`, `set-cookie`, `request-id`, `x-request-id`, `x-amzn-trace-id`

  ### Cassette Format

  Cassettes are stored as JSONL files in `test/support/cassettes/`:

      {"key":"GET https://api.example.com/users -","req":{...},"resp":{...}}
      {"key":"POST https://api.example.com/users abc123...","req":{...},"resp":{...}}

  ## Workflow

      # 1. Write tests using Reqord.Case
      # 2. Record cassettes (hits live API)
      REQORD=record API_TOKEN=xxx mix test

      # 3. Commit cassettes to git
      git add test/support/cassettes/
      git commit -m "Add API cassettes"

      # 4. Run tests in replay mode (no network calls)
      mix test

      # 5. Update cassettes when API changes
      REQORD=record API_TOKEN=xxx mix test

  ## Integration with Req.Test

  Reqord works alongside your existing `Req.Test` stubs:

      test "with mixed stubs" do
        # Add a high-priority stub for specific URL
        Req.Test.stub(MyApp.ReqStub, fn
          %{request_path: "/special"} = conn ->
            Req.Test.json(conn, %{special: true})
        end)

        client = Req.new(plug: {Req.Test, MyApp.ReqStub})

        # This hits your stub
        {:ok, resp1} = Req.get(client, url: "https://api.example.com/special")
        assert resp1.body["special"] == true

        # This falls through to VCR
        {:ok, resp2} = Req.get(client, url: "https://api.example.com/other")
      end
  """

  require Logger

  alias Reqord.{Cassette, CassetteEntry, Config, Record, Replay}

  @type mode :: :once | :new_episodes | :all | :none
  @type matcher :: :method | :uri | :host | :path | :headers | :body | atom()
  @type matcher_fun :: (Plug.Conn.t(), map() -> boolean())

  # Custom matcher registry
  @custom_matchers :reqord_custom_matchers

  @doc """
  Registers a custom matcher function.

  Custom matchers receive the incoming `Plug.Conn` and a cassette entry,
  and return `true` if they match.

  ## Examples

      # Register a custom matcher that checks request ID header
      Reqord.register_matcher(:request_id, fn conn, entry ->
        req_id = Plug.Conn.get_req_header(conn, "x-request-id") |> List.first()
        req_id == get_in(entry, ["req", "headers", "x-request-id"])
      end)

      # Use the custom matcher
      Reqord.install!(
        name: MyApp.ReqStub,
        cassette: "my_test",
        match_on: [:method, :uri, :request_id]
      )
  """
  @spec register_matcher(atom(), matcher_fun()) :: :ok
  def register_matcher(name, fun) when is_atom(name) and is_function(fun, 2) do
    matchers = :persistent_term.get(@custom_matchers, %{})
    :persistent_term.put(@custom_matchers, Map.put(matchers, name, fun))
    :ok
  end

  @doc """
  Clears all registered custom matchers.

  Useful for test cleanup.
  """
  @spec clear_matchers() :: :ok
  def clear_matchers do
    :persistent_term.put(@custom_matchers, %{})
    :ok
  end

  defmodule CassetteMissError do
    defexception [:message, :method, :url, :body_hash, :cassette]

    @impl true
    def message(%{method: method, url: url, body_hash: body_hash, cassette: cassette}) do
      """
      No cassette entry found for request:

        Method:    #{method}
        URL:       #{url}
        Body hash: #{body_hash}
        Cassette:  #{cassette}

      To record this request, run:
        REQORD=record mix test --include vcr

      Or use auto mode to record on misses:
        REQORD=auto mix test
      """
    end
  end

  @doc """
  Installs a VCR stub that handles cassette replay and recording.

  ## Options

  - `:name` - Required. The name of the `Req.Test` stub to use
  - `:cassette` - Required. The cassette file name (without extension)
  - `:mode` - The VCR record mode. Defaults to `:once`
  - `:match_on` - List of matchers to use. Defaults to `[:method, :uri]`

  ## Record Modes

  Reqord supports Ruby VCR-style record modes:

  - `:once` - Use existing cassette, raise on new requests (strict replay, default)
  - `:new_episodes` - Use existing cassette, record new requests (append mode)
  - `:all` - Always hit live network and re-record everything
  - `:none` - Never record, never hit network (must have complete cassette)

  ## Request Matching

  Built-in matchers:
  - `:method` - Match HTTP method (GET, POST, etc.)
  - `:uri` - Match full normalized URI (default with :method)
  - `:host` - Match only the host
  - `:path` - Match only the path (without query string)
  - `:headers` - Match request headers
  - `:body` - Match request body content

  You can also register custom matchers with `register_matcher/2`.

  ## Examples

      # Default matching (method + uri)
      Reqord.install!(
        name: MyApp.ReqStub,
        cassette: "my_test",
        mode: :once
      )

      # Match on method, path, and body (useful for APIs with changing query params)
      Reqord.install!(
        name: MyApp.ReqStub,
        cassette: "my_test",
        match_on: [:method, :path, :body]
      )

      # Match only on method and host (ignores path and query)
      Reqord.install!(
        name: MyApp.ReqStub,
        cassette: "my_test",
        match_on: [:method, :host]
      )

      # Use custom matcher
      Reqord.register_matcher(:api_version, fn conn, entry ->
        Plug.Conn.get_req_header(conn, "x-api-version") ==
          [get_in(entry, ["req", "headers", "x-api-version"])]
      end)

      Reqord.install!(
        name: MyApp.ReqStub,
        cassette: "my_test",
        match_on: [:method, :uri, :api_version]
      )
  """
  @spec install!(keyword()) :: :ok
  def install!(opts) do
    name = Keyword.fetch!(opts, :name)
    cassette = Keyword.fetch!(opts, :cassette)
    mode = Keyword.get(opts, :mode, :once)
    match_on = Keyword.get(opts, :match_on, [:method, :uri])

    cassette_path = cassette_path(cassette)

    # Install a catch-all stub that handles all requests
    Req.Test.stub(name, fn conn ->
      # Reload entries on each request for :all mode to see newly recorded entries
      entries = Cassette.load(cassette_path)

      handle_request(conn, name, cassette_path, entries, mode, match_on)
    end)

    :ok
  end

  @doc """
  Allows a spawned process to use the VCR stub.

  ## Examples

      test "with spawned process" do
        task = Task.async(fn ->
          Reqord.allow(MyApp.ReqStub, self(), Task.async(fn -> ... end).pid)
          # spawned process can now make requests
        end)
        Task.await(task)
      end
  """
  @spec allow(atom(), pid(), pid()) :: :ok
  def allow(name, owner_pid, allowed_pid) do
    Req.Test.allow(name, owner_pid, allowed_pid)
  end

  # Private functions

  defp handle_request(conn, name, cassette_path, entries, mode, match_on) do
    # Extract request details
    method = conn.method |> to_string() |> String.upcase()
    url = build_url(conn)
    body = Req.Test.raw_body(conn)

    # Handle request based on mode - following Ruby VCR behavior
    case mode do
      :all ->
        # Always record, never replay (Ruby VCR behavior)
        Record.record_request(conn, name, cassette_path, method, url, body, :all)

      :none ->
        handle_none_mode(conn, entries, match_on, method, url, body, cassette_path)

      :once ->
        handle_once_mode(conn, entries, match_on, method, url, body, cassette_path)

      :new_episodes ->
        handle_new_episodes_mode(conn, name, cassette_path, method, url, body, entries, match_on)
    end
  end

  defp handle_none_mode(conn, entries, match_on, method, url, body, cassette_path) do
    # Never record, only replay
    case find_matching_entry(entries, conn, match_on) do
      {:ok, entry} ->
        Replay.replay_response(conn, entry)

      :not_found ->
        raise CassetteMissError,
          method: method,
          url: url,
          body_hash: compute_body_hash(method, body),
          cassette: cassette_path
    end
  end

  defp handle_once_mode(conn, entries, match_on, method, url, body, cassette_path) do
    # Record once, then replay
    case find_matching_entry(entries, conn, match_on) do
      {:ok, entry} ->
        Replay.replay_response(conn, entry)

      :not_found ->
        raise CassetteMissError,
          method: method,
          url: url,
          body_hash: compute_body_hash(method, body),
          cassette: cassette_path
    end
  end

  defp handle_new_episodes_mode(conn, name, cassette_path, method, url, body, entries, match_on) do
    # Replay if found, record if not found
    case find_matching_entry(entries, conn, match_on) do
      {:ok, entry} ->
        Replay.replay_response(conn, entry)

      :not_found ->
        Record.record_request(conn, name, cassette_path, method, url, body, :new_episodes)
    end
  end

  # Find matching entry using flexible matchers
  # Uses "last match wins" strategy to handle appended cassettes correctly
  defp find_matching_entry(entries, conn, match_on) do
    # Find all matching entries and take the last one (most recent)
    matching_entries = Enum.filter(entries, &matches_request?(&1, conn, match_on))

    case List.last(matching_entries) do
      nil -> :not_found
      entry -> {:ok, entry}
    end
  end

  # Check if an entry matches the request based on the given matchers
  defp matches_request?(entry, conn, matchers) do
    Enum.all?(matchers, fn matcher ->
      apply_matcher(matcher, conn, entry)
    end)
  end

  # Apply a specific matcher
  defp apply_matcher(:method, conn, %CassetteEntry{req: req}) do
    method = conn.method |> to_string() |> String.upcase()
    method == req.method
  end

  defp apply_matcher(:uri, conn, %CassetteEntry{req: req}) do
    url = build_url(conn)
    normalized_url = normalize_url(url)
    normalized_url == normalize_url(req.url)
  end

  defp apply_matcher(:host, conn, %CassetteEntry{req: req}) do
    conn.host == (URI.parse(req.url).host || "")
  end

  defp apply_matcher(:path, conn, %CassetteEntry{req: req}) do
    conn.request_path == (URI.parse(req.url).path || "")
  end

  defp apply_matcher(:headers, conn, %CassetteEntry{req: req}) do
    req_headers = conn.req_headers |> Enum.into(%{})
    entry_headers = req.headers

    # Normalize both sets of headers
    normalized_req = normalize_headers(req_headers)
    normalized_entry = normalize_headers(entry_headers)

    # Compare: all entry headers must be present in request headers with same values
    # Request can have additional headers
    Enum.all?(normalized_entry, fn {key, value} ->
      Map.get(normalized_req, key) == value
    end)
  end

  defp apply_matcher(:body, conn, %CassetteEntry{req: req}) do
    body = Req.Test.raw_body(conn)
    entry_body_hash = req.body_hash

    # Compare body hash
    method = conn.method |> to_string() |> String.upcase()
    compute_body_hash(method, body) == entry_body_hash
  end

  # Check for custom matchers
  defp apply_matcher(matcher_name, conn, entry) when is_atom(matcher_name) do
    custom_matchers = :persistent_term.get(@custom_matchers, %{})

    case Map.get(custom_matchers, matcher_name) do
      nil ->
        # Unknown matcher - log warning and default to false
        require Logger
        Logger.warning("Unknown matcher: #{inspect(matcher_name)}")
        false

      matcher_fun ->
        matcher_fun.(conn, entry)
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Enum.sort()
    |> Enum.into(%{})
  end

  defp build_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    port_part = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    query_part = if conn.query_string == "", do: "", else: "?#{conn.query_string}"

    "#{scheme}://#{conn.host}#{port_part}#{conn.request_path}#{query_part}"
  end

  defp normalize_url(url) do
    uri = URI.parse(url)

    # Sort query parameters and remove auth params
    normalized_query =
      if uri.query do
        filtered =
          uri.query
          |> URI.decode_query()
          |> Enum.reject(fn {key, _} -> String.downcase(key) in Config.auth_params() end)
          |> Enum.sort()

        # If all params were filtered out, set to nil to remove the ? from URL
        case filtered do
          [] -> nil
          params -> URI.encode_query(params)
        end
      else
        nil
      end

    %{uri | query: normalized_query}
    |> URI.to_string()
  end

  defp compute_body_hash(method, body) do
    if method in ["POST", "PUT", "PATCH"] and body != "" do
      :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    else
      "-"
    end
  end

  defp cassette_path(name) do
    Config.cassette_path(name)
  end
end
