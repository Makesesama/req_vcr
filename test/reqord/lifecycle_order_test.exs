defmodule Reqord.LifecycleOrderTest do
  @moduledoc """
  Test to reproduce the issue where POST-DELETE lifecycle requests
  get recorded in the wrong order, causing mismatches during replay.
  """

  use Reqord.Case
  alias Reqord.{CassetteReader, CassetteWriter}
  import Reqord.TestHelpers

  @moduletag :integration

  @test_api_port 4001
  @test_api_url "http://localhost:#{@test_api_port}"

  defp default_stub_name, do: Reqord.LifecycleOrderStub

  @tag integration: "LifecycleOrderTest/post_delete_lifecycle_maintains_order"
  @tag vcr_mode: :all
  test "POST-DELETE lifecycle should maintain correct order" do
    # Clear cassette to ensure clean start for :all mode
    cassette_path =
      "test/support/cassettes/LifecycleOrderTest/post_delete_lifecycle_maintains_order.jsonl"

    clear_cassette_for_all_mode(cassette_path)

    # This test simulates a typical create-delete lifecycle
    # where a resource is created with POST and immediately deleted

    client =
      Req.new(
        plug: {Req.Test, Reqord.LifecycleOrderStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    # First lifecycle: Create user 3, then delete it
    {:ok, create_resp1} =
      Req.post(client,
        url: "#{@test_api_url}/api/users",
        json: %{name: "User Three", email: "user3@example.com"}
      )

    assert create_resp1.status == 201
    assert create_resp1.body["id"] == 3

    {:ok, delete_resp1} = Req.delete(client, url: "#{@test_api_url}/api/users/3")
    assert delete_resp1.status == 200
    assert delete_resp1.body["message"] == "User 3 deleted"

    # Second lifecycle: Create another user 3, then delete it again
    # This simulates a test that runs the same lifecycle multiple times
    {:ok, create_resp2} =
      Req.post(client,
        url: "#{@test_api_url}/api/users",
        json: %{name: "Another User Three", email: "another3@example.com"}
      )

    assert create_resp2.status == 201
    assert create_resp2.body["id"] == 3

    {:ok, delete_resp2} = Req.delete(client, url: "#{@test_api_url}/api/users/3")
    assert delete_resp2.status == 200
    assert delete_resp2.body["message"] == "User 3 deleted"

    # Flush the writer to ensure all entries are written
    cassette_path =
      "test/support/cassettes/LifecycleOrderTest/post_delete_lifecycle_maintains_order.jsonl"

    CassetteWriter.flush_cassette(cassette_path)

    assert File.exists?(cassette_path), "Cassette file should exist"

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 4, "All 4 requests should be recorded"

    # Verify the order is correct: POST, DELETE, POST, DELETE
    [entry1, entry2, entry3, entry4] = entries

    assert entry1.req.method == "POST", "First entry should be POST"
    assert entry1.req.url =~ "/api/users"
    assert entry1.req.body_hash != "-", "POST should have body"

    assert entry2.req.method == "DELETE", "Second entry should be DELETE"
    assert entry2.req.url =~ "/api/users/3"

    assert entry3.req.method == "POST", "Third entry should be POST"
    assert entry3.req.url =~ "/api/users"
    assert entry3.req.body_hash != "-", "POST should have body"

    assert entry4.req.method == "DELETE", "Fourth entry should be DELETE"
    assert entry4.req.url =~ "/api/users/3"
  end

  @tag integration: "LifecycleOrderTest/concurrent_lifecycles_test"
  @tag vcr_mode: :all
  test "concurrent POST-DELETE lifecycles may get mixed up" do
    # Clear cassette to ensure clean start for :all mode
    cassette_path = "test/support/cassettes/LifecycleOrderTest/concurrent_lifecycles_test.jsonl"
    clear_cassette_for_all_mode(cassette_path)

    # This test simulates concurrent requests where multiple lifecycles
    # might interleave, causing order issues

    client =
      Req.new(
        plug: {Req.Test, Reqord.LifecycleOrderStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    # Spawn multiple tasks to simulate concurrent lifecycles
    tasks =
      for i <- 1..3 do
        Task.async(fn ->
          # Each task does a POST-DELETE lifecycle
          {:ok, create_resp} =
            Req.post(client,
              url: "#{@test_api_url}/api/users",
              json: %{name: "Concurrent User #{i}", email: "concurrent#{i}@example.com"}
            )

          # Small random delay to simulate real-world timing variations
          Process.sleep(:rand.uniform(10))

          {:ok, delete_resp} = Req.delete(client, url: "#{@test_api_url}/api/users/3")

          {create_resp, delete_resp}
        end)
      end

    # Wait for all tasks to complete
    results = Task.await_many(tasks, 5000)

    # Verify all requests succeeded
    Enum.each(results, fn {create_resp, delete_resp} ->
      assert create_resp.status == 201
      assert delete_resp.status == 200
    end)

    # Flush the writer to ensure all entries are written
    cassette_path =
      "test/support/cassettes/LifecycleOrderTest/concurrent_lifecycles_test.jsonl"

    CassetteWriter.flush_cassette(cassette_path)

    assert File.exists?(cassette_path), "Cassette file should exist"

    entries = CassetteReader.load_entries(cassette_path)
    assert length(entries) == 6, "All 6 requests should be recorded (3 POST + 3 DELETE)"

    # Check if the order might be mixed (not strictly POST-DELETE pairs)
    # This could happen if requests are recorded as they complete, not as they're initiated
    methods = Enum.map(entries, fn entry -> entry.req.method end)

    IO.puts("Recorded order: #{inspect(methods)}")

    # In a problematic scenario, we might see something like:
    # ["POST", "POST", "DELETE", "POST", "DELETE", "DELETE"]
    # instead of ["POST", "DELETE", "POST", "DELETE", "POST", "DELETE"]

    # Count consecutive same methods as potential issue indicator
    consecutive_same =
      methods
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> a == b end)

    if consecutive_same > 0 do
      IO.puts("WARNING: Found #{consecutive_same} consecutive same-method requests")
      IO.puts("This indicates potential ordering issues in concurrent scenarios")
    end
  end
end
