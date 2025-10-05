defmodule Reqord.CassetteReader do
  @moduledoc """
  Module for reading cassette entries with chronological timestamp ordering.

  The CassetteReader is part of Reqord's new architecture that ensures
  requests are replayed in the exact chronological order they were recorded,
  solving concurrent request ordering issues.

  ## Features

  - **Timestamp sorting**: Automatically sorts entries by `recorded_at` for chronological replay
  - **Streaming reads**: Memory-efficient processing of large cassette files
  - **Storage backend support**: Works with any storage backend implementing `Reqord.Storage.Behavior`
  - **Error resilience**: Gracefully handles malformed entries with logging

  ## Usage

      # Load all entries sorted by timestamp
      entries = CassetteReader.load_entries("path/to/cassette.jsonl")

      # Or stream for memory efficiency (not sorted)
      entries = CassetteReader.stream_entries("path/to/cassette.jsonl")

      # Check if cassette exists
      if CassetteReader.exists?("path/to/cassette.jsonl") do
        # Load and process entries
      end

  ## Timestamp Ordering

  The reader ensures that regardless of how entries were written to the cassette
  (potentially out of order due to concurrent requests), they are loaded in
  chronological order based on their `recorded_at` timestamps:

      # Even if cassette contains: POST (t=200), DELETE (t=100), POST (t=300)
      # Reader returns: DELETE (t=100), POST (t=200), POST (t=300)

  This guarantees that request/response lifecycles are replayed correctly,
  preventing ID mismatch errors in concurrent testing scenarios.
  """

  alias Reqord.CassetteEntry

  require Logger

  @doc """
  Load all entries from a cassette file, sorted by timestamp.

  Uses streaming for memory efficiency during parsing, then sorts in memory.
  For very large cassettes, consider using `stream_entries/2` if you don't need sorting.

  ## Parameters
    - `cassette_path` - Path to the cassette file
    - `storage_backend` - Storage backend module (defaults to FileSystem)

  ## Returns
    - List of CassetteEntry structs sorted by recorded_at timestamp
  """
  def load_entries(cassette_path, storage_backend \\ Reqord.Storage.FileSystem) do
    cassette_path
    |> storage_backend.read_entries()
    |> stream_parse_and_sort()
  end

  @doc """
  Load entries as a stream for memory-efficient processing.

  Note: The stream is NOT sorted by timestamp. Use `load_entries/2` if you need sorted entries.
  """
  def stream_entries(cassette_path, storage_backend \\ Reqord.Storage.FileSystem) do
    cassette_path
    |> storage_backend.read_entries()
    |> Stream.map(&parse_entry/1)
    |> Stream.reject(&is_nil/1)
  end

  @doc """
  Check if a cassette exists.
  """
  def exists?(cassette_path, storage_backend \\ Reqord.Storage.FileSystem) do
    storage_backend.exists?(cassette_path)
  end

  # Private functions

  defp parse_entry(entry_map) when is_map(entry_map) do
    case CassetteEntry.from_raw(entry_map) do
      {:ok, entry} ->
        entry

      {:error, reason} ->
        Logger.warning("Failed to parse cassette entry: #{inspect(reason)}")
        nil
    end
  end

  defp parse_entry(_), do: nil

  # Optimized streaming parse and sort
  defp stream_parse_and_sort(raw_entries_stream) do
    # For better memory efficiency, we can use a streaming approach
    # that parses entries lazily but still needs to collect for sorting
    raw_entries_stream
    |> Stream.map(&parse_entry/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.sort_by(& &1.recorded_at)
  end
end
