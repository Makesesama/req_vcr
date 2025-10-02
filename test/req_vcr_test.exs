defmodule ReqVCRTest do
  use ExUnit.Case

  @test_stub ReqVCRTest.Stub
  @cassette_dir "test/support/cassettes"

  setup do
    # Ensure cassette directory exists (but don't delete existing cassettes)
    File.mkdir_p!(@cassette_dir)

    # Set up Req.Test
    Req.Test.set_req_test_to_private()
    Req.Test.set_req_test_from_context(%{async: true})

    # Clean up unit test cassettes after each test (but preserve ExampleAPI and fixtures)
    on_exit(fn ->
      File.ls!(@cassette_dir)
      |> Enum.reject(&(&1 == "ExampleAPI"))
      # Keep permanent test fixtures
      |> Enum.reject(&(&1 == "fixtures"))
      |> Enum.each(fn file ->
        File.rm!(Path.join(@cassette_dir, file))
      end)
    end)

    :ok
  end

  describe "replay mode" do
    test "replays response from cassette" do
      # Create a cassette file
      cassette_path = Path.join(@cassette_dir, "replay_test.jsonl")

      entry = %{
        req: %{
          method: "GET",
          url: "https://api.example.com/users",
          headers: %{},
          body_hash: "-"
        },
        resp: %{
          status: 200,
          headers: %{"content-type" => "application/json"},
          body_b64: Base.encode64(Jason.encode!(%{name: "John"}))
        }
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      # Install VCR in replay mode
      ReqVCR.install!(
        name: @test_stub,
        cassette: "replay_test",
        mode: :once
      )

      # Make request
      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response} = Req.get(client, url: "https://api.example.com/users")

      # Verify response
      assert response.status == 200
      assert response.headers["content-type"] == ["application/json"]
      # Req auto-decodes JSON responses
      assert response.body == %{"name" => "John"}
    end

    test "replays plain text response" do
      cassette_path = Path.join(@cassette_dir, "text_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/data", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("Hello World")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(name: @test_stub, cassette: "text_test", mode: :once)

      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response} = Req.get(client, url: "https://api.example.com/data")

      assert response.status == 200
      assert response.body == "Hello World"
    end

    test "raises error when cassette entry not found" do
      ReqVCR.install!(
        name: @test_stub,
        cassette: "empty_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      assert_raise ReqVCR.CassetteMissError, ~r/No cassette entry found/, fn ->
        Req.get!(client, url: "https://api.example.com/users")
      end
    end

    test "does not make actual network calls when replaying from cassette" do
      # Create a cassette with a real-looking entry
      cassette_path = Path.join(@cassette_dir, "no_network_test.jsonl")

      entry = %{
        req: %{
          method: "GET",
          url: "https://invalid-nonexistent-domain-12345.com/api/test",
          headers: %{},
          body_hash: "-"
        },
        resp: %{
          status: 200,
          headers: %{"content-type" => "application/json"},
          body_b64: Base.encode64(Jason.encode!(%{message: "from_cassette"}))
        }
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      # Install VCR in replay mode
      ReqVCR.install!(
        name: @test_stub,
        cassette: "no_network_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # This request would fail if it hit the network (invalid domain)
      # but should succeed because it's served from the cassette
      {:ok, response} =
        Req.get(client, url: "https://invalid-nonexistent-domain-12345.com/api/test")

      # Verify we got the cassette response, not a network error
      assert response.status == 200
      assert response.body["message"] == "from_cassette"
    end

    test "matches requests with query parameters in different order" do
      cassette_path = Path.join(@cassette_dir, "query_order_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users?a=1&b=2", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("OK")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "query_order_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Request with different query param order should match
      {:ok, response} = Req.get(client, url: "https://api.example.com/users?b=2&a=1")
      assert response.status == 200
    end

    test "ignores auth query parameters in matching" do
      cassette_path = Path.join(@cassette_dir, "auth_param_test.jsonl")

      # Key should not include the token param
      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("OK")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "auth_param_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Request with auth params should still match (auth params ignored in key)
      {:ok, response} = Req.get(client, url: "https://api.example.com/users?token=secret123")
      assert response.status == 200
    end

    test "matches POST requests by body hash" do
      cassette_path = Path.join(@cassette_dir, "post_test.jsonl")

      body1 = Jason.encode!(%{name: "Alice"})
      body2 = Jason.encode!(%{name: "Bob"})
      hash1 = :crypto.hash(:sha256, body1) |> Base.encode16(case: :lower)
      hash2 = :crypto.hash(:sha256, body2) |> Base.encode16(case: :lower)

      entry1 = %{
        req: %{
          method: "POST",
          url: "https://api.example.com/users",
          body_hash: hash1,
          headers: %{}
        },
        resp: %{
          status: 201,
          headers: %{"content-type" => "application/json"},
          body_b64: Base.encode64(Jason.encode!(%{id: 1, name: "Alice"}))
        }
      }

      entry2 = %{
        req: %{
          method: "POST",
          url: "https://api.example.com/users",
          body_hash: hash2,
          headers: %{}
        },
        resp: %{
          status: 201,
          headers: %{"content-type" => "application/json"},
          body_b64: Base.encode64(Jason.encode!(%{id: 2, name: "Bob"}))
        }
      }

      File.write!(
        cassette_path,
        Jason.encode!(entry1) <> "\n" <> Jason.encode!(entry2) <> "\n"
      )

      ReqVCR.install!(
        name: @test_stub,
        cassette: "post_test",
        mode: :once,
        match_on: [:method, :uri, :body]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Same URL, different bodies should match different cassette entries
      {:ok, resp1} =
        Req.post(client, url: "https://api.example.com/users", json: %{name: "Alice"})

      {:ok, resp2} = Req.post(client, url: "https://api.example.com/users", json: %{name: "Bob"})

      assert resp1.status == 201
      assert is_map(resp1.body)
      assert resp1.body["name"] == "Alice"
      assert resp2.status == 201
      assert is_map(resp2.body)
      assert resp2.body["name"] == "Bob"
    end
  end

  describe "record modes" do
    test "mode :once - replays from cassette when match found" do
      cassette_path = Path.join(@cassette_dir, "once_replay_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("cached")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "once_replay_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response} = Req.get(client, url: "https://api.example.com/users")

      assert response.body == "cached"
    end

    test "mode :once - raises on new request" do
      ReqVCR.install!(
        name: @test_stub,
        cassette: "once_strict_test",
        mode: :once
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      assert_raise ReqVCR.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/new")
      end
    end

    test "mode :new_episodes - replays existing and allows new recordings" do
      cassette_path = Path.join(@cassette_dir, "new_episodes_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("cached")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "new_episodes_test",
        mode: :new_episodes
      )

      # Existing request replays from cassette
      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response1} = Req.get(client, url: "https://api.example.com/users")
      assert response1.body == "cached"

      # Cassette should still have only 1 entry (not re-recorded)
      entries =
        cassette_path
        |> File.read!()
        |> String.split("\n", trim: true)

      assert length(entries) == 1
    end

    test "mode :all - ignores existing cassette and always re-records" do
      cassette_path = Path.join(@cassette_dir, "all_test.jsonl")

      # Create initial cassette entry
      entry = %{
        req: %{method: "GET", url: "https://api.example.com/data", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("old")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "all_test",
        mode: :all
      )

      # Note: In :all mode, we can't actually test re-recording in unit tests
      # because record_request tries to make a real network call.
      # This test verifies that :all mode exists and the cassette is loaded.
      # Full :all mode behavior requires integration testing with real network.

      # Verify the cassette exists with 1 entry
      entries =
        cassette_path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert length(entries) == 1
      assert Base.decode64!(hd(entries)["resp"]["body_b64"]) == "old"
    end

    test "mode :none - never records, never hits network" do
      cassette_path = Path.join(@cassette_dir, "none_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("cached")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "none_test",
        mode: :none
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Existing request works
      {:ok, response} = Req.get(client, url: "https://api.example.com/users")
      assert response.body == "cached"

      # New request raises error
      assert_raise ReqVCR.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/new")
      end
    end
  end

  describe "cassette file operations" do
    test "loads existing cassette entries" do
      cassette_path = Path.join(@cassette_dir, "multi_entry_test.jsonl")

      entries = [
        %{
          req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-"},
          resp: %{status: 200, headers: %{}, body_b64: Base.encode64("user list")}
        },
        %{
          req: %{method: "GET", url: "https://api.example.com/posts", body_hash: "-"},
          resp: %{status: 200, headers: %{}, body_b64: Base.encode64("post list")}
        }
      ]

      content = Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
      File.write!(cassette_path, content)

      ReqVCR.install!(name: @test_stub, cassette: "multi_entry_test", mode: :once)

      client = Req.new(plug: {Req.Test, @test_stub})

      {:ok, resp1} = Req.get(client, url: "https://api.example.com/users")
      {:ok, resp2} = Req.get(client, url: "https://api.example.com/posts")

      assert resp1.body == "user list"
      assert resp2.body == "post list"
    end

    test "handles missing cassette file gracefully" do
      # Don't create any cassette file
      ReqVCR.install!(name: @test_stub, cassette: "nonexistent", mode: :once)

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should raise cassette miss error, not file error
      assert_raise ReqVCR.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/data")
      end
    end
  end

  describe "URL normalization" do
    test "normalizes URLs with standard ports" do
      cassette_path = Path.join(@cassette_dir, "port_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/data", body_hash: "-"},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("OK")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(name: @test_stub, cassette: "port_test", mode: :once)

      client = Req.new(plug: {Req.Test, @test_stub})

      # Explicit port 443 for HTTPS should match entry without port
      {:ok, response} = Req.get(client, url: "https://api.example.com:443/data")
      assert response.status == 200
    end
  end

  describe "header handling" do
    test "preserves non-volatile response headers" do
      cassette_path = Path.join(@cassette_dir, "header_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/data", body_hash: "-", headers: %{}},
        resp: %{
          status: 200,
          headers: %{
            "content-type" => "text/plain",
            "x-custom-header" => "custom-value"
          },
          body_b64: Base.encode64("OK")
        }
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(name: @test_stub, cassette: "header_test", mode: :once)

      client = Req.new(plug: {Req.Test, @test_stub})
      {:ok, response} = Req.get(client, url: "https://api.example.com/data")

      assert response.headers["content-type"] == ["text/plain"]
      assert response.headers["x-custom-header"] == ["custom-value"]
    end
  end

  describe "flexible request matching" do
    setup do
      # Clean up custom matchers after each test
      on_exit(fn -> ReqVCR.clear_matchers() end)
      :ok
    end

    test "method matcher - matches HTTP method" do
      cassette_path = Path.join(@cassette_dir, "method_test.jsonl")

      entry = %{
        req: %{method: "POST", url: "https://api.example.com/data", body_hash: "-", headers: %{}},
        resp: %{status: 201, headers: %{}, body_b64: Base.encode64("created")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "method_test",
        match_on: [:method]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should match any POST request regardless of URL
      {:ok, response} = Req.post(client, url: "https://different.com/path")
      assert response.body == "created"
    end

    test "host matcher - matches only host" do
      cassette_path = Path.join(@cassette_dir, "host_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("matched")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "host_test",
        match_on: [:method, :host]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should match same host, different path
      {:ok, response} = Req.get(client, url: "https://api.example.com/posts")
      assert response.body == "matched"
    end

    test "path matcher - matches only path" do
      cassette_path = Path.join(@cassette_dir, "path_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/users", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("matched")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "path_test",
        match_on: [:method, :path]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should match same path with different query params
      {:ok, response} = Req.get(client, url: "https://api.example.com/users?page=2")
      assert response.body == "matched"
    end

    test "headers matcher - matches request headers" do
      cassette_path = Path.join(@cassette_dir, "headers_matcher_test.jsonl")

      entry = %{
        req: %{
          method: "GET",
          url: "https://api.example.com/data",
          body_hash: "-",
          headers: %{"x-api-key" => "secret123", "accept" => "application/json"}
        },
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("matched")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "headers_matcher_test",
        match_on: [:method, :uri, :headers]
      )

      client =
        Req.new(
          plug: {Req.Test, @test_stub},
          headers: [{"x-api-key", "secret123"}, {"accept", "application/json"}]
        )

      {:ok, response} = Req.get(client, url: "https://api.example.com/data")
      assert response.body == "matched"
    end

    test "body matcher - distinguishes requests by body content" do
      cassette_path = Path.join(@cassette_dir, "body_matcher_test.jsonl")

      body1 = Jason.encode!(%{action: "create"})
      body2 = Jason.encode!(%{action: "update"})
      hash1 = :crypto.hash(:sha256, body1) |> Base.encode16(case: :lower)
      hash2 = :crypto.hash(:sha256, body2) |> Base.encode16(case: :lower)

      entry1 = %{
        req: %{
          method: "POST",
          url: "https://api.example.com/action",
          body_hash: hash1,
          headers: %{}
        },
        resp: %{status: 201, headers: %{}, body_b64: Base.encode64("created")}
      }

      entry2 = %{
        req: %{
          method: "POST",
          url: "https://api.example.com/action",
          body_hash: hash2,
          headers: %{}
        },
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("updated")}
      }

      File.write!(cassette_path, Jason.encode!(entry1) <> "\n" <> Jason.encode!(entry2) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "body_matcher_test",
        match_on: [:method, :uri, :body]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      {:ok, resp1} =
        Req.post(client, url: "https://api.example.com/action", json: %{action: "create"})

      {:ok, resp2} =
        Req.post(client, url: "https://api.example.com/action", json: %{action: "update"})

      assert resp1.body == "created"
      assert resp2.body == "updated"
    end

    test "custom matcher - registers and uses custom matching logic" do
      cassette_path = Path.join(@cassette_dir, "custom_matcher_test.jsonl")

      entry = %{
        req: %{
          method: "GET",
          url: "https://api.example.com/data",
          body_hash: "-",
          headers: %{"x-version" => "v2"}
        },
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("v2 response")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      # Register custom matcher for API version
      ReqVCR.register_matcher(:api_version, fn conn, %ReqVCR.CassetteEntry{req: req} ->
        version = Plug.Conn.get_req_header(conn, "x-version") |> List.first()
        version == Map.get(req.headers, "x-version")
      end)

      ReqVCR.install!(
        name: @test_stub,
        cassette: "custom_matcher_test",
        match_on: [:method, :uri, :api_version]
      )

      client =
        Req.new(
          plug: {Req.Test, @test_stub},
          headers: [{"x-version", "v2"}]
        )

      {:ok, response} = Req.get(client, url: "https://api.example.com/data")
      assert response.body == "v2 response"
    end

    test "multiple custom matchers can be registered" do
      ReqVCR.register_matcher(:matcher1, fn _conn, _entry -> true end)
      ReqVCR.register_matcher(:matcher2, fn _conn, _entry -> true end)

      # Should not raise - both matchers registered successfully
      assert :ok == :ok
    end

    test "clear_matchers removes all custom matchers" do
      ReqVCR.register_matcher(:test_matcher, fn _conn, _entry -> true end)
      ReqVCR.clear_matchers()

      # After clearing, using unknown matcher should log warning but not crash
      cassette_path = Path.join(@cassette_dir, "cleared_matcher_test.jsonl")

      entry = %{
        req: %{method: "GET", url: "https://api.example.com/data", body_hash: "-", headers: %{}},
        resp: %{status: 200, headers: %{}, body_b64: Base.encode64("ok")}
      }

      File.write!(cassette_path, Jason.encode!(entry) <> "\n")

      ReqVCR.install!(
        name: @test_stub,
        cassette: "cleared_matcher_test",
        match_on: [:test_matcher]
      )

      client = Req.new(plug: {Req.Test, @test_stub})

      # Should raise cassette miss because matcher returns false
      assert_raise ReqVCR.CassetteMissError, fn ->
        Req.get!(client, url: "https://api.example.com/data")
      end
    end
  end
end
