defmodule Reqord.AllModeDeletionFixTest do
  @moduledoc """
  Test to verify the fix for the :all mode cassette deletion bug.

  This test ensures that cassettes are never deleted prematurely,
  and only replaced when we have new data ready to write.
  """

  use ExUnit.Case
  alias Reqord.{CassetteEntry, CassetteState, CassetteWriter, Storage.FileSystem}

  @test_dir Path.join(System.tmp_dir!(), "reqord_all_mode_deletion_fix_test")

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

  test "cassette is not deleted prematurely in :all mode", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "test_cassette.jsonl")

    # Create existing cassette with some data
    existing_entry = create_test_entry("GET", "https://api.example.com/users", "old data")
    FileSystem.ensure_path_exists(cassette_path)
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(existing_entry))

    # Verify cassette exists with content
    assert File.exists?(cassette_path)
    existing_content = File.read!(cassette_path)
    assert String.contains?(existing_content, Base.encode64("old data"))

    # Simulate :all mode behavior - start cassette state
    CassetteState.start_for_cassette(cassette_path)

    # Check if this would be considered "first request" (empty state)
    current_entries = CassetteState.get_entries(cassette_path)
    assert Enum.empty?(current_entries)

    # With the old buggy code, the cassette would be deleted here.
    # With the fix, it should NOT be deleted.

    # Verify cassette still exists (was not deleted prematurely)
    assert File.exists?(cassette_path)
    still_existing_content = File.read!(cassette_path)
    assert String.contains?(still_existing_content, Base.encode64("old data"))

    # Add a new entry to the writer
    new_entry = create_test_entry("POST", "https://api.example.com/users", "new data")
    entry_map = CassetteEntry.to_map(new_entry)
    CassetteWriter.write_entry(cassette_path, entry_map)

    # The cassette should still contain the old data until we explicitly replace it
    current_content = File.read!(cassette_path)
    assert String.contains?(current_content, Base.encode64("old data"))
    # New data should not be in the file yet (it's in the writer's buffer)
    refute String.contains?(current_content, Base.encode64("new data"))

    # Now call the replacement function (which happens during cleanup)
    CassetteWriter.replace_cassette_for_all_mode(cassette_path)

    # NOW the cassette should be replaced with the new data
    final_content = File.read!(cassette_path)
    assert String.contains?(final_content, Base.encode64("new data"))
    # Old data should be gone
    refute String.contains?(final_content, Base.encode64("old data"))

    # Clean up
    CassetteState.stop_for_cassette(cassette_path)
  end

  test "replacement only happens when there are entries to replace", %{test_dir: test_dir} do
    cassette_path = Path.join(test_dir, "empty_replacement_test.jsonl")

    # Create existing cassette
    existing_entry = create_test_entry("GET", "https://api.example.com/data", "preserved data")
    FileSystem.ensure_path_exists(cassette_path)
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(existing_entry))

    # Verify cassette exists
    assert File.exists?(cassette_path)
    original_content = File.read!(cassette_path)

    # Try to replace with no pending entries
    CassetteWriter.replace_cassette_for_all_mode(cassette_path)

    # Cassette should be unchanged since there were no entries to replace with
    final_content = File.read!(cassette_path)
    assert final_content == original_content
    assert String.contains?(final_content, Base.encode64("preserved data"))
  end

  test "cleanup function properly handles :all mode vs other modes", %{test_dir: test_dir} do
    # Configure the cassette directory to point to our test directory
    original_dir = Application.get_env(:reqord, :cassette_dir)
    Application.put_env(:reqord, :cassette_dir, test_dir)

    # Use simple cassette name that will be resolved by Config.cassette_path
    cassette_name = "cleanup_mode_test"
    cassette_path = Reqord.Config.cassette_path(cassette_name)

    # Create existing cassette
    existing_entry = create_test_entry("GET", "https://api.example.com/test", "original")
    FileSystem.ensure_path_exists(cassette_path)
    FileSystem.write_entry(cassette_path, CassetteEntry.to_map(existing_entry))

    # Test cleanup with :once mode (should append, not replace)
    CassetteState.start_for_cassette(cassette_path)
    new_entry = create_test_entry("POST", "https://api.example.com/test", "new in once mode")
    entry_map = CassetteEntry.to_map(new_entry)
    CassetteWriter.write_entry(cassette_path, entry_map)

    # Force flush to ensure the entry is written to the file
    CassetteWriter.flush_cassette(cassette_path)

    # Read content to verify both entries are present (appended, not replaced)
    content_after_once = File.read!(cassette_path)
    assert String.contains?(content_after_once, Base.encode64("original"))
    assert String.contains?(content_after_once, Base.encode64("new in once mode"))

    # Cleanup with :once mode (should not change anything since we already flushed)
    Reqord.cleanup(cassette_name, :once)

    # Test cleanup with :all mode (should replace)
    CassetteState.start_for_cassette(cassette_path)

    all_mode_entry =
      create_test_entry("PUT", "https://api.example.com/test", "replaced in all mode")

    entry_map_all = CassetteEntry.to_map(all_mode_entry)
    CassetteWriter.write_entry(cassette_path, entry_map_all)

    # Cleanup with :all mode
    Reqord.cleanup(cassette_name, :all)

    # Should have only the new entry (replaced, not appended)
    content_after_all = File.read!(cassette_path)
    refute String.contains?(content_after_all, Base.encode64("original"))
    refute String.contains?(content_after_all, Base.encode64("new in once mode"))
    assert String.contains?(content_after_all, Base.encode64("replaced in all mode"))

    # Restore original cassette directory config
    if original_dir do
      Application.put_env(:reqord, :cassette_dir, original_dir)
    else
      Application.delete_env(:reqord, :cassette_dir)
    end
  end

  # Helper function
  defp create_test_entry(method, url, response_body, status \\ 200) do
    {:ok, req} = CassetteEntry.Request.new(method, url, %{}, "-")
    {:ok, resp} = CassetteEntry.Response.new(status, %{}, Base.encode64(response_body))
    {:ok, entry} = CassetteEntry.new(req, resp)
    entry
  end
end
