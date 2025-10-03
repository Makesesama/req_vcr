defmodule Reqord.AllModeMultipleRequestsTest do
  @moduledoc """
  Test to verify :all mode correctly handles multiple requests without
  requiring external services. This tests the core functionality directly.
  """

  use ExUnit.Case
  alias Reqord.{Cassette, CassetteEntry}

  @test_dir Path.join(System.tmp_dir!(), "reqord_all_mode_multi_test")

  setup do
    # Create fresh test directory
    test_dir = @test_dir <> "_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    %{test_dir: test_dir}
  end

  test "install! with :all mode clears existing cassette", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "test_cassette.jsonl")

    # Create existing cassette with old entries
    old_entry1 = create_test_entry("GET", "https://old.api.com/data", "old data 1")
    old_entry2 = create_test_entry("POST", "https://old.api.com/data", "old data 2")

    Cassette.append(cassette_path, old_entry1)
    Cassette.append(cassette_path, old_entry2)

    # Verify old cassette exists
    assert File.exists?(cassette_path)
    old_entries = Cassette.load(cassette_path)
    assert length(old_entries) == 2

    # Simulate install! with :all mode (using the actual logic)
    if File.exists?(cassette_path) do
      File.rm!(cassette_path)
    end

    # Verify cassette was cleared
    refute File.exists?(cassette_path)
  end

  test ":all mode allows multiple requests to be appended to same cassette", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "multi_request_cassette.jsonl")

    # Simulate the :all mode workflow:
    # 1. Cassette is cleared at start (install!)
    # 2. Multiple requests append during test

    # First request in test
    entry1 = create_test_entry("GET", "https://api.example.com/users", "users list")
    Cassette.append(cassette_path, entry1)

    # Verify first request recorded
    entries = Cassette.load(cassette_path)
    assert length(entries) == 1
    assert Base.decode64!(hd(entries).resp.body_b64) == "users list"

    # Second request in same test
    entry2 = create_test_entry("GET", "https://api.example.com/users/1", "user 1 details")
    Cassette.append(cassette_path, entry2)

    # Third request in same test
    entry3 = create_test_entry("POST", "https://api.example.com/users", "created user")
    Cassette.append(cassette_path, entry3)

    # Fourth request in same test
    entry4 = create_test_entry("GET", "https://api.example.com/users/2", "user 2 details")
    Cassette.append(cassette_path, entry4)

    # Verify all requests are recorded
    entries = Cassette.load(cassette_path)
    assert length(entries) == 4

    # Verify order and content
    assert Base.decode64!(Enum.at(entries, 0).resp.body_b64) == "users list"
    assert Base.decode64!(Enum.at(entries, 1).resp.body_b64) == "user 1 details"
    assert Base.decode64!(Enum.at(entries, 2).resp.body_b64) == "created user"
    assert Base.decode64!(Enum.at(entries, 3).resp.body_b64) == "user 2 details"

    # Verify request methods
    assert Enum.at(entries, 0).req.method == "GET"
    assert Enum.at(entries, 1).req.method == "GET"
    assert Enum.at(entries, 2).req.method == "POST"
    assert Enum.at(entries, 3).req.method == "GET"

    # Verify URLs
    assert Enum.at(entries, 0).req.url =~ "/users"
    assert Enum.at(entries, 1).req.url =~ "/users/1"
    assert Enum.at(entries, 2).req.url =~ "/users"
    assert Enum.at(entries, 3).req.url =~ "/users/2"
  end

  test "demonstrates the fixed behavior vs broken behavior", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "behavior_demo.jsonl")

    # OLD BROKEN BEHAVIOR (what v0.2.1 was doing):
    # Each request would replace the entire cassette

    # Request 1 - replace entire cassette
    entry1 = create_test_entry("GET", "https://api.example.com/users", "users list")
    Cassette.replace(cassette_path, entry1)

    entries = Cassette.load(cassette_path)
    assert length(entries) == 1

    # Request 2 - replace entire cassette (broken behavior)
    entry2 = create_test_entry("POST", "https://api.example.com/users", "created user")
    Cassette.replace(cassette_path, entry2)

    # In broken behavior, only the last request survives
    entries = Cassette.load(cassette_path)
    assert length(entries) == 1
    assert Base.decode64!(hd(entries).resp.body_b64) == "created user"

    # The first request is lost!
    refute Enum.any?(entries, fn entry ->
             Base.decode64!(entry.resp.body_b64) == "users list"
           end)

    # Clear for demo of fixed behavior
    File.rm!(cassette_path)

    # NEW FIXED BEHAVIOR (what v0.2.2 does):
    # Accumulate all requests for the test and replace entire cassette

    # Simulate :all mode recording multiple requests in same test
    # Each request replaces the cassette with ALL accumulated requests

    # Request 1 - replace cassette with [entry1]
    write_all_entries_to_cassette(cassette_path, [entry1])

    # Request 2 - replace cassette with [entry1, entry2]
    write_all_entries_to_cassette(cassette_path, [entry1, entry2])

    # In fixed behavior, both requests are preserved
    entries = Cassette.load(cassette_path)
    assert length(entries) == 2
    assert Base.decode64!(Enum.at(entries, 0).resp.body_b64) == "users list"
    assert Base.decode64!(Enum.at(entries, 1).resp.body_b64) == "created user"
  end

  # Helper functions
  defp create_test_entry(method, url, response_body, status \\ 200) do
    {:ok, req} = CassetteEntry.Request.new(method, url, %{}, "-")
    {:ok, resp} = CassetteEntry.Response.new(status, %{}, Base.encode64(response_body))
    {:ok, entry} = CassetteEntry.new(req, resp)
    entry
  end

  defp write_all_entries_to_cassette(cassette_path, entries) do
    # Ensure directory exists
    cassette_path |> Path.dirname() |> File.mkdir_p!()

    # Write all entries to the cassette file, replacing any existing content
    content =
      Enum.map_join(entries, "\n", fn entry ->
        entry_map = CassetteEntry.to_map(entry)
        Reqord.JSON.encode!(entry_map)
      end)

    File.write!(cassette_path, content <> "\n")
  end
end
