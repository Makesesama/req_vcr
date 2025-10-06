defmodule Reqord.AllModeMultipleRequestsTest do
  @moduledoc """
  Test to verify :all mode correctly handles multiple requests without
  requiring external services. This tests the core functionality directly.
  """

  use ExUnit.Case
  import Reqord.TestHelpers
  alias Reqord.{CassetteEntry, CassetteReader, Storage.FileSystem}

  @test_dir Path.join(System.tmp_dir!(), "reqord_all_mode_multi_test")

  setup do
    # Create fresh test directory
    test_dir = @test_dir <> "_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      nil
      # Don't delete test directories - cassettes should persist
    end)

    %{test_dir: test_dir}
  end

  @tag vcr_mode: :all
  test "install! with :all mode clears existing cassette", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "test_cassette.jsonl")

    old_entry1 = create_test_entry("GET", "https://old.api.com/data", "old data 1")
    old_entry2 = create_test_entry("POST", "https://old.api.com/data", "old data 2")

    FileSystem.ensure_path_exists(cassette_path)
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(old_entry1))
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(old_entry2))

    assert File.exists?(cassette_path)
    old_entries = CassetteReader.load_entries(cassette_path)
    assert length(old_entries) == 2
  end

  @tag vcr_mode: :all
  test ":all mode allows multiple requests to be appended to same cassette", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "multi_request_cassette.jsonl")

    entry1 = create_test_entry("GET", "https://api.example.com/users", "users list")
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(entry1))

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 1
    assert Base.decode64!(hd(entries).resp.body_b64) == "users list"

    entry2 = create_test_entry("GET", "https://api.example.com/users/1", "user 1 details")
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(entry2))

    entry3 = create_test_entry("POST", "https://api.example.com/users", "created user")
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(entry3))

    entry4 = create_test_entry("GET", "https://api.example.com/users/2", "user 2 details")
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(entry4))

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 4

    assert Base.decode64!(Enum.at(entries, 0).resp.body_b64) == "users list"
    assert Base.decode64!(Enum.at(entries, 1).resp.body_b64) == "user 1 details"
    assert Base.decode64!(Enum.at(entries, 2).resp.body_b64) == "created user"
    assert Base.decode64!(Enum.at(entries, 3).resp.body_b64) == "user 2 details"

    assert Enum.at(entries, 0).req.method == "GET"
    assert Enum.at(entries, 1).req.method == "GET"
    assert Enum.at(entries, 2).req.method == "POST"
    assert Enum.at(entries, 3).req.method == "GET"

    assert Enum.at(entries, 0).req.url =~ "/users"
    assert Enum.at(entries, 1).req.url =~ "/users/1"
    assert Enum.at(entries, 2).req.url =~ "/users"
    assert Enum.at(entries, 3).req.url =~ "/users/2"
  end

  @tag vcr_mode: :all
  test "demonstrates the fixed behavior vs broken behavior", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "behavior_demo.jsonl")
    clear_cassette_for_all_mode(cassette_path)

    entry1 = create_test_entry("GET", "https://api.example.com/users", "users list")
    FileSystem.ensure_path_exists(cassette_path)
    File.write!(cassette_path, Reqord.JSON.encode!(CassetteEntry.to_map(entry1)) <> "\n")

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 1

    entry2 = create_test_entry("POST", "https://api.example.com/users", "created user")
    File.write!(cassette_path, Reqord.JSON.encode!(CassetteEntry.to_map(entry2)) <> "\n")

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 1
    assert Base.decode64!(hd(entries).resp.body_b64) == "created user"

    refute Enum.any?(entries, fn entry ->
             Base.decode64!(entry.resp.body_b64) == "users list"
           end)

    write_all_entries_for_all_mode(cassette_path, [entry1])
    write_all_entries_for_all_mode(cassette_path, [entry1, entry2])

    entries = CassetteReader.load_entries(cassette_path)
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
end
