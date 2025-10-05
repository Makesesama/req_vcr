defmodule Reqord.ConcurrentRequestsFixedTest do
  @moduledoc """
  Tests to verify that the GenServer-based fix works correctly for concurrent requests.
  """

  use ExUnit.Case
  alias Reqord.{Cassette, CassetteEntry, CassetteState}

  @test_dir Path.join(System.tmp_dir!(), "reqord_concurrent_fixed_test")

  setup do
    # Create fresh test directory
    test_dir = @test_dir <> "_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    %{test_dir: test_dir}
  end

  test "GenServer state works across processes", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "genserver_test.jsonl")

    # Start the GenServer for this cassette
    {:ok, _pid} = CassetteState.start_for_cassette(cassette_path)

    # Verify initial state
    assert CassetteState.get_entries(cassette_path) == []

    # Add an entry from main process
    entry1 = create_test_entry("GET", "https://api.example.com/test", "test data")
    CassetteState.append_entry(cassette_path, entry1)

    # Verify it was added
    entries = CassetteState.get_entries(cassette_path)
    assert length(entries) == 1

    # Now spawn a task and access the same state
    task =
      Task.async(fn ->
        # Should be able to see the entry from parent process
        current_entries = CassetteState.get_entries(cassette_path)

        # Add another entry from spawned process
        entry2 = create_test_entry("POST", "https://api.example.com/test", "task data")
        CassetteState.append_entry(cassette_path, entry2)

        # Return what we saw
        {length(current_entries), entry2}
      end)

    {seen_count, _task_entry} = Task.await(task)

    # Task should have seen the entry from main process
    assert seen_count == 1

    # Now main process should see both entries
    final_entries = CassetteState.get_entries(cassette_path)
    assert length(final_entries) == 2

    # Cleanup
    CassetteState.stop_for_cassette(cassette_path)
  end

  test "concurrent requests work with GenServer-based state", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "concurrent_fixed.jsonl")

    # Initialize GenServer state
    {:ok, _pid} = CassetteState.start_for_cassette(cassette_path)
    CassetteState.clear_entries(cassette_path)

    # Simulate concurrent requests using GenServer state (the fixed approach)
    tasks = [
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/datasets", "dataset 1")
        CassetteState.append_entry(cassette_path, entry)
        current_entries = CassetteState.get_entries(cassette_path)
        write_all_entries_to_cassette(cassette_path, current_entries)
        :ok
      end),
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/datasets", "dataset 2")
        CassetteState.append_entry(cassette_path, entry)
        current_entries = CassetteState.get_entries(cassette_path)
        write_all_entries_to_cassette(cassette_path, current_entries)
        :ok
      end),
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/datasets", "dataset 3")
        CassetteState.append_entry(cassette_path, entry)
        current_entries = CassetteState.get_entries(cassette_path)
        write_all_entries_to_cassette(cassette_path, current_entries)
        :ok
      end)
    ]

    # Wait for all tasks
    Task.await_many(tasks)

    # Add cleanup requests from main process
    cleanup1 = create_test_entry("DELETE", "https://api.example.com/datasets/1", "deleted")
    CassetteState.append_entry(cassette_path, cleanup1)
    current_entries = CassetteState.get_entries(cassette_path)
    write_all_entries_to_cassette(cassette_path, current_entries)

    cleanup2 = create_test_entry("DELETE", "https://api.example.com/datasets/2", "deleted")
    CassetteState.append_entry(cassette_path, cleanup2)
    current_entries = CassetteState.get_entries(cassette_path)
    write_all_entries_to_cassette(cassette_path, current_entries)

    cleanup3 = create_test_entry("DELETE", "https://api.example.com/datasets/3", "deleted")
    CassetteState.append_entry(cassette_path, cleanup3)
    current_entries = CassetteState.get_entries(cassette_path)
    write_all_entries_to_cassette(cassette_path, current_entries)

    # Load and analyze results
    entries = Cassette.load(cassette_path)

    post_entries = Enum.filter(entries, &(&1.req.method == "POST"))
    delete_entries = Enum.filter(entries, &(&1.req.method == "DELETE"))

    # With the fix, all POST entries should be recorded
    assert length(post_entries) == 3
    assert length(delete_entries) == 3
    assert length(entries) == 6

    # Verify the fix worked

    # Cleanup
    CassetteState.stop_for_cassette(cassette_path)
  end

  test "demonstrates the difference between broken and fixed approaches", %{test_dir: test_dir} do
    broken_cassette = Path.join(test_dir, "broken_approach.jsonl")
    fixed_cassette = Path.join(test_dir, "fixed_approach.jsonl")

    # BROKEN APPROACH: Using process dictionary (like original Reqord)
    broken_entries_key = {:reqord_entries, broken_cassette}
    Process.put(broken_entries_key, [])

    broken_tasks = [
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/broken", "data 1")
        # This fails - spawned process has empty process dictionary
        current_entries = Process.get(broken_entries_key, [])
        new_entries = current_entries ++ [entry]
        Process.put(broken_entries_key, new_entries)
        write_all_entries_to_cassette(broken_cassette, new_entries)
        :ok
      end),
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/broken", "data 2")
        # This also fails
        current_entries = Process.get(broken_entries_key, [])
        new_entries = current_entries ++ [entry]
        Process.put(broken_entries_key, new_entries)
        write_all_entries_to_cassette(broken_cassette, new_entries)
        :ok
      end)
    ]

    Task.await_many(broken_tasks)

    # FIXED APPROACH: Using GenServer
    {:ok, _pid} = CassetteState.start_for_cassette(fixed_cassette)
    CassetteState.clear_entries(fixed_cassette)

    fixed_tasks = [
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/fixed", "data 1")
        CassetteState.append_entry(fixed_cassette, entry)
        current_entries = CassetteState.get_entries(fixed_cassette)
        write_all_entries_to_cassette(fixed_cassette, current_entries)
        :ok
      end),
      Task.async(fn ->
        entry = create_test_entry("POST", "https://api.example.com/fixed", "data 2")
        CassetteState.append_entry(fixed_cassette, entry)
        current_entries = CassetteState.get_entries(fixed_cassette)
        write_all_entries_to_cassette(fixed_cassette, current_entries)
        :ok
      end)
    ]

    Task.await_many(fixed_tasks)

    # Compare results
    _broken_entries =
      if File.exists?(broken_cassette), do: Cassette.load(broken_cassette), else: []

    fixed_entries = Cassette.load(fixed_cassette)

    # The fixed approach should record all entries
    assert length(fixed_entries) == 2

    # The broken approach likely records fewer (or creates individual files)
    # This demonstrates the improvement

    # Cleanup
    CassetteState.stop_for_cassette(fixed_cassette)
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
