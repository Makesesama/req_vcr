defmodule Reqord.MultipleRequestsIntegrationTest do
  @moduledoc """
  Integration test to verify :all mode works correctly with multiple requests
  in a single test using the local test API.

  ## Setup Required

  These tests require the test API to be running. Start it with:

      cd test_api && mix run --no-halt

  Then run the tests with:

      mix test test/reqord/multiple_requests_integration_test.exs --include integration
  """

  use Reqord.Case
  alias Reqord.{CassetteEntry, CassetteReader, CassetteWriter, JSON}

  @moduletag :integration

  @test_api_port 4001
  @test_api_url "http://localhost:#{@test_api_port}"

  defp default_stub_name, do: Reqord.MultipleRequestsIntegrationStub

  @tag vcr: "ExampleAPI/multiple_requests_in_all_mode_are_all_recorded_properly"
  test "multiple requests in :all mode are all recorded properly" do
    # Make multiple different requests to ensure they're all recorded

    # Request 1: GET all users
    client =
      Req.new(
        plug: {Req.Test, Reqord.MultipleRequestsIntegrationStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    {:ok, resp1} = Req.get(client, url: "#{@test_api_url}/api/users")
    assert resp1.status == 200
    assert is_list(resp1.body)
    assert length(resp1.body) == 2

    # Request 2: GET specific user
    {:ok, resp2} = Req.get(client, url: "#{@test_api_url}/api/users/1")
    assert resp2.status == 200
    assert resp2.body["id"] == 1
    assert resp2.body["name"] == "Alice"

    # Request 3: POST new user
    {:ok, resp3} =
      Req.post(client,
        url: "#{@test_api_url}/api/users",
        json: %{name: "Charlie", email: "charlie@example.com"}
      )

    assert resp3.status == 201
    assert resp3.body["id"] == 3
    assert resp3.body["name"] == "Charlie"

    # Request 4: GET another specific user
    {:ok, resp4} = Req.get(client, url: "#{@test_api_url}/api/users/2")
    assert resp4.status == 200
    assert resp4.body["id"] == 2
    assert resp4.body["name"] == "Bob"

    # Now verify that all 4 requests were recorded in the cassette
    cassette_path =
      "test/support/cassettes/ExampleAPI/multiple_requests_in_all_mode_are_all_recorded_properly.jsonl"

    # Flush the writer to ensure all entries are written
    CassetteWriter.flush_cassette(cassette_path)

    assert File.exists?(cassette_path), "Cassette file should exist"

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 4, "All 4 requests should be recorded"

    # Verify each request is correctly recorded
    [entry1, entry2, entry3, entry4] = entries

    assert entry1.req.method == "GET"
    assert entry1.req.url =~ "/api/users"
    # Should not have ID in URL
    refute entry1.req.url =~ "/api/users/"

    assert entry2.req.method == "GET"
    assert entry2.req.url =~ "/api/users/1"

    assert entry3.req.method == "POST"
    assert entry3.req.url =~ "/api/users"
    # POST should have body hash
    assert entry3.req.body_hash != "-"

    assert entry4.req.method == "GET"
    assert entry4.req.url =~ "/api/users/2"
  end

  @tag vcr:
         "ExampleAPI/rerecording_with_all_mode_clears_old_cassette_and_records_all_new_requests"
  @tag :all_mode_only
  test "rerecording with :all mode clears old cassette and records all new requests" do
    # This test simulates the workflow of fixing a bug and rerecording

    # First, let's pretend there's an existing cassette with old/broken data
    cassette_path =
      "test/support/cassettes/ExampleAPI/rerecording_with_all_mode_clears_old_cassette_and_records_all_new_requests.jsonl"

    # Create a fresh cassette with "old" data for this test
    old_entry1 = create_test_entry("GET", "http://localhost:4001/api/old", "old data 1")
    old_entry2 = create_test_entry("POST", "http://localhost:4001/api/old", "old data 2")

    File.mkdir_p!(Path.dirname(cassette_path))
    # Replace any existing cassette with just these 2 entries
    write_all_entries_to_cassette(cassette_path, [old_entry1, old_entry2])

    # Verify old cassette exists with exactly 2 entries
    assert File.exists?(cassette_path)
    old_entries = CassetteReader.load_entries(cassette_path)
    assert length(old_entries) == 2

    # Now the test runs (simulating rerecording after fixing code)
    # The :all mode should clear the old cassette and record fresh

    # These requests simulate the "fixed" code making correct API calls
    client =
      Req.new(
        plug: {Req.Test, Reqord.MultipleRequestsIntegrationStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    {:ok, resp1} = Req.get(client, url: "#{@test_api_url}/api/users")
    assert resp1.status == 200

    {:ok, resp2} =
      Req.post(client,
        url: "#{@test_api_url}/api/users",
        json: %{name: "Diana", email: "diana@example.com"}
      )

    assert resp2.status == 201

    {:ok, resp3} = Req.get(client, url: "#{@test_api_url}/api/users/1")
    assert resp3.status == 200

    # Flush the writer to ensure all entries are written
    CassetteWriter.flush_cassette(cassette_path)

    # Verify the cassette now has only the new requests (old ones cleared)
    new_entries = CassetteReader.load_entries(cassette_path)
    assert length(new_entries) == 3, "Should have exactly 3 new requests, old ones cleared"

    # Verify none of the old entries exist
    Enum.each(new_entries, fn entry ->
      refute entry.req.url =~ "/api/old", "Old entries should be completely gone"
    end)

    # Verify the new entries are correct
    assert Enum.at(new_entries, 0).req.url =~ "/api/users"
    assert Enum.at(new_entries, 1).req.method == "POST"
    assert Enum.at(new_entries, 2).req.url =~ "/api/users/1"
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
        JSON.encode!(entry_map)
      end)

    File.write!(cassette_path, content <> "\n")
  end
end
