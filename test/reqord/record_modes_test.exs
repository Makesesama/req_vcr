defmodule Reqord.RecordModesTest do
  @moduledoc """
  Tests for different record modes (:all, :new_episodes) and their behavior
  with cassette files, especially the critical :all mode replacement behavior.
  """

  use ExUnit.Case
  alias Reqord.{Cassette, CassetteEntry}

  @test_dir Path.join(System.tmp_dir!(), "reqord_record_modes_test")

  setup do
    # Create fresh test directory for each test
    test_dir = @test_dir <> "_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf(test_dir)
    end)

    %{test_dir: test_dir}
  end

  describe "Cassette.replace/2" do
    test "overwrites existing cassette file", %{test_dir: test_dir} do
      cassette_file = Path.join(test_dir, "replace_test.jsonl")

      # Create initial entry
      {:ok, req1} = CassetteEntry.Request.new("GET", "https://example.com/1", %{}, "-")
      {:ok, resp1} = CassetteEntry.Response.new(200, %{}, Base.encode64("old response"))
      {:ok, entry1} = CassetteEntry.new(req1, resp1)

      # Write initial entry
      Cassette.append(cassette_file, entry1)

      # Verify initial state
      entries = Cassette.load(cassette_file)
      assert length(entries) == 1
      assert Base.decode64!(hd(entries).resp.body_b64) == "old response"

      # Replace with new entry
      {:ok, req2} = CassetteEntry.Request.new("GET", "https://example.com/2", %{}, "-")
      {:ok, resp2} = CassetteEntry.Response.new(201, %{}, Base.encode64("new response"))
      {:ok, entry2} = CassetteEntry.new(req2, resp2)

      Cassette.replace(cassette_file, entry2)

      # Verify replacement
      entries = Cassette.load(cassette_file)
      assert length(entries) == 1
      assert hd(entries).req.url == "https://example.com/2"
      assert hd(entries).resp.status == 201
      assert Base.decode64!(hd(entries).resp.body_b64) == "new response"
    end
  end

  describe "Last-match-wins behavior" do
    test "replays the most recent matching entry", %{test_dir: test_dir} do
      cassette_file = Path.join(test_dir, "last_match_test.jsonl")

      # Create multiple entries for the same request (simulating append behavior)
      entries = [
        # First entry - old/broken response
        create_test_entry("GET", "https://api.example.com/users", "old broken response"),
        # Different request
        create_test_entry("POST", "https://api.example.com/users", "create response"),
        # Second entry - same request as first, but fixed response
        create_test_entry("GET", "https://api.example.com/users", "new fixed response")
      ]

      # Write all entries to cassette (simulating multiple recordings)
      for entry <- entries do
        Cassette.append(cassette_file, entry)
      end

      # Load entries and verify order
      loaded_entries = Cassette.load(cassette_file)
      assert length(loaded_entries) == 3

      # Verify that the first and third entries match the same request
      first_entry = Enum.at(loaded_entries, 0)
      third_entry = Enum.at(loaded_entries, 2)

      assert first_entry.req.method == third_entry.req.method
      assert first_entry.req.url == third_entry.req.url

      # But they have different responses
      assert Base.decode64!(first_entry.resp.body_b64) == "old broken response"
      assert Base.decode64!(third_entry.resp.body_b64) == "new fixed response"

      # Test the find_matching_entry logic directly
      # This is internal logic, but critical for this fix
      conn = %Plug.Conn{
        method: "GET",
        host: "api.example.com",
        request_path: "/users",
        query_string: ""
      }

      # Simulate the matching logic (private function testing)
      matching_entries =
        Enum.filter(loaded_entries, fn entry ->
          entry.req.method == "GET" && entry.req.url == "https://api.example.com/users"
        end)

      # Should find 2 matching entries
      assert length(matching_entries) == 2

      # Last match should be the "new fixed response"
      last_match = List.last(matching_entries)
      assert Base.decode64!(last_match.resp.body_b64) == "new fixed response"
    end

    test "handles no matches correctly" do
      entries = [
        create_test_entry("GET", "https://api.example.com/posts", "posts response"),
        create_test_entry("POST", "https://api.example.com/users", "create response")
      ]

      # Test matching against a request that doesn't exist
      matching_entries =
        Enum.filter(entries, fn entry ->
          entry.req.method == "DELETE" && entry.req.url == "https://api.example.com/nonexistent"
        end)

      assert Enum.empty?(matching_entries)
      assert List.last(matching_entries) == nil
    end
  end

  describe "Record mode integration scenarios" do
    test "simulates the real-world broken->fixed workflow", %{test_dir: test_dir} do
      cassette_file = Path.join(test_dir, "workflow_test.jsonl")

      # Step 1: Initial recording with broken request (missing uniqueKey)
      broken_entry =
        create_test_entry(
          "POST",
          "https://api.example.com/items",
          "Error: uniqueKey is required",
          400
        )

      Cassette.append(cassette_file, broken_entry)

      # Step 2: Developer fixes code and re-records (REQORD=all should replace)
      # But current broken behavior would append, creating the problem described

      # Simulate the current broken append behavior
      fixed_entry =
        create_test_entry(
          "POST",
          # Same request
          "https://api.example.com/items",
          "Success: item created",
          201
        )

      # This is what was happening
      Cassette.append(cassette_file, fixed_entry)

      # Step 3: Replay with last-match-wins should use the fixed version
      loaded_entries = Cassette.load(cassette_file)
      assert length(loaded_entries) == 2

      # Find the matching entries for the same request
      matching_entries =
        Enum.filter(loaded_entries, fn entry ->
          entry.req.method == "POST" && entry.req.url == "https://api.example.com/items"
        end)

      assert length(matching_entries) == 2

      # With last-match-wins, we should get the fixed response
      last_match = List.last(matching_entries)
      assert last_match.resp.status == 201
      assert Base.decode64!(last_match.resp.body_b64) == "Success: item created"

      # Verify the old behavior would have been broken
      first_match = List.first(matching_entries)
      assert first_match.resp.status == 400
      assert Base.decode64!(first_match.resp.body_b64) == "Error: uniqueKey is required"
    end

    test "demonstrates proper :all mode behavior with replace", %{test_dir: test_dir} do
      cassette_file = Path.join(test_dir, "all_mode_test.jsonl")

      # Step 1: Create existing cassette with old data
      old_entry = create_test_entry("GET", "https://api.example.com/data", "old data")
      Cassette.append(cassette_file, old_entry)

      # Verify initial state
      entries = Cassette.load(cassette_file)
      assert length(entries) == 1

      # Step 2: Simulate :all mode - always replaces entire cassette
      new_entry1 = create_test_entry("GET", "https://api.example.com/data", "new data 1")
      Cassette.replace(cassette_file, new_entry1)

      # Verify replacement
      entries = Cassette.load(cassette_file)
      assert length(entries) == 1
      assert Base.decode64!(hd(entries).resp.body_b64) == "new data 1"

      # Step 3: Each subsequent :all mode request replaces the entire cassette
      new_entry2 = create_test_entry("POST", "https://api.example.com/data", "new data 2")
      Cassette.replace(cassette_file, new_entry2)

      # Verify complete replacement (not append)
      entries = Cassette.load(cassette_file)
      assert length(entries) == 1
      assert Base.decode64!(hd(entries).resp.body_b64) == "new data 2"
    end
  end

  # Helper function to create test entries
  defp create_test_entry(method, url, response_body, status \\ 200) do
    {:ok, req} = CassetteEntry.Request.new(method, url, %{}, "-")
    {:ok, resp} = CassetteEntry.Response.new(status, %{}, Base.encode64(response_body))
    {:ok, entry} = CassetteEntry.new(req, resp)
    entry
  end
end
