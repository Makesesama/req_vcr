defmodule Reqord.TimestampOrderingTest do
  @moduledoc """
  Test to verify that timestamp-based ordering ensures correct replay
  even when requests are recorded out of order.
  """

  use ExUnit.Case
  import Reqord.TestHelpers
  alias Reqord.{CassetteReader, CassetteWriter}

  @tag vcr_mode: :all
  test "entries are sorted by timestamp when reading" do
    cassette_path = "test/support/cassettes/test_timestamp_ordering.jsonl"
    clear_cassette_for_all_mode(cassette_path)

    # Create entries with specific timestamps (out of order)
    entries = [
      create_entry("POST", "/users", "user3", 300),
      create_entry("DELETE", "/users/1", "deleted1", 150),
      create_entry("POST", "/users", "user1", 100),
      create_entry("DELETE", "/users/3", "deleted3", 350),
      create_entry("POST", "/users", "user2", 200),
      create_entry("DELETE", "/users/2", "deleted2", 250)
    ]

    # Write entries out of order using CassetteWriter (which sorts by timestamp)
    Enum.each(entries, fn entry ->
      CassetteWriter.write_entry(cassette_path, entry)
    end)

    # Force flush to ensure all entries are written and sorted
    CassetteWriter.flush_cassette(cassette_path)

    # Read entries back - they should be sorted by timestamp
    loaded_entries = CassetteReader.load_entries(cassette_path)

    # Verify the order is correct (sorted by timestamp)
    assert length(loaded_entries) == 6

    timestamps = Enum.map(loaded_entries, & &1.recorded_at)
    assert timestamps == [100, 150, 200, 250, 300, 350]

    # Verify the actual order of operations
    methods = Enum.map(loaded_entries, & &1.req.method)
    urls = Enum.map(loaded_entries, & &1.req.url)

    assert methods == ["POST", "DELETE", "POST", "DELETE", "POST", "DELETE"]
    assert urls == ["/users", "/users/1", "/users", "/users/2", "/users", "/users/3"]

    # No cleanup needed - never delete cassettes
  end

  @tag vcr_mode: :all
  test "CassetteWriter batches and sorts entries before writing" do
    cassette_path = "test/support/cassettes/test_writer_batching.jsonl"
    clear_cassette_for_all_mode(cassette_path)

    # Never delete cassettes - tests should only append

    # Write entries with timestamps out of order
    CassetteWriter.write_entry(cassette_path, create_entry("POST", "/users", "user2", 200))
    CassetteWriter.write_entry(cassette_path, create_entry("POST", "/users", "user1", 100))
    CassetteWriter.write_entry(cassette_path, create_entry("DELETE", "/users/1", "deleted", 150))

    # Force flush to write immediately
    CassetteWriter.flush_cassette(cassette_path)

    # Read back and verify they're sorted
    loaded_entries = CassetteReader.load_entries(cassette_path)

    assert length(loaded_entries) == 3
    timestamps = Enum.map(loaded_entries, & &1.recorded_at)
    assert timestamps == [100, 150, 200]

    # No cleanup needed - never delete cassettes
  end

  # Helper to create a cassette entry map with specific timestamp
  defp create_entry(method, url, body, timestamp) do
    %{
      "req" => %{
        "method" => method,
        "url" => url,
        "headers" => %{"content-type" => "application/json"},
        "body_hash" =>
          if(method == "DELETE", do: "-", else: :crypto.hash(:sha256, body) |> Base.encode16())
      },
      "resp" => %{
        "status" => if(method == "DELETE", do: 200, else: 201),
        "headers" => %{"content-type" => "application/json"},
        "body_b64" => Base.encode64(body)
      },
      "recorded_at" => timestamp
    }
  end
end
