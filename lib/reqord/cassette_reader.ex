defmodule Reqord.CassetteReader do
  @moduledoc """
  Module for reading cassette entries in their stored order.

  The CassetteReader is part of Reqord's new architecture that reads
  cassette entries efficiently without any additional processing.

  ## Features

  - **Streaming reads**: Memory-efficient processing of large cassette files
  - **Storage backend support**: Works with any storage backend implementing `Reqord.Storage.Behavior`
  - **Error resilience**: Gracefully handles malformed entries with logging

  ## Usage

      # Load all entries in stored order
      entries = CassetteReader.load_entries("path/to/cassette.jsonl")

      # Or stream for memory efficiency
      entries = CassetteReader.stream_entries("path/to/cassette.jsonl")

      # Check if cassette exists
      if CassetteReader.exists?("path/to/cassette.jsonl") do
        # Load and process entries
      end

  ## Ordering Guarantee

  Entries are returned in the order they appear in the cassette file.
  Since the CassetteWriter sorts entries by timestamp before writing,
  the stored order is already chronological.
  """

  alias Reqord.CassetteEntry

  require Logger

  @doc """
  Load all entries from a cassette file in stored order.

  Uses streaming for memory efficiency during parsing.

  ## Parameters
    - `cassette_path` - Path to the cassette file
    - `storage_backend` - Storage backend module (defaults to FileSystem)

  ## Returns
    - List of CassetteEntry structs in stored order
  """
  def load_entries(cassette_path, storage_backend \\ Reqord.Storage.FileSystem) do
    cassette_path
    |> storage_backend.read_entries()
    |> stream_parse()
  end

  @doc """
  Load entries as a stream for memory-efficient processing.

  Returns entries in stored order without loading all into memory at once.
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

  defp stream_parse(raw_entries_stream) do
    raw_entries_stream
    |> Stream.map(&parse_entry/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
  end
end
