defmodule Reqord.Storage.FileSystem do
  @moduledoc """
  FileSystem storage backend implementation.

  This module provides file-based storage for cassette entries using JSONL format.
  It implements streaming reads/writes for memory efficiency and provides atomic
  operations for concurrent safety.
  """

  @behaviour Reqord.Storage.Behavior

  alias Reqord.JSON

  @doc """
  Write a single entry to the specified cassette file.
  Appends to the file in JSONL format.
  """
  @impl true
  def write_entry(path, entry) when is_map(entry) do
    ensure_path_exists(path)

    content = JSON.encode!(entry) <> "\n"

    # Use atomic write with :append flag
    case File.write(path, content, [:append]) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to write entry: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Failed to encode entry: #{Exception.message(e)}"}
  end

  @doc """
  Stream all entries from the specified cassette file.
  Returns a Stream that lazily reads and parses JSONL entries.
  """
  @impl true
  def read_entries(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&parse_line/1)
      |> Stream.reject(&is_nil/1)
    else
      # Return empty stream if file doesn't exist
      Stream.map([], & &1)
    end
  end

  @doc """
  Delete an entire cassette file.
  """
  @impl true
  def delete_cassette(path) do
    case File.rm(path) do
      :ok -> :ok
      # File doesn't exist is okay
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, "Failed to delete cassette: #{inspect(reason)}"}
    end
  end

  @doc """
  Ensure the directory structure for a cassette path exists.
  """
  @impl true
  def ensure_path_exists(path) do
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create directory: #{inspect(reason)}"}
    end
  end

  @doc """
  Check if a cassette exists at the specified path.
  """
  @impl true
  def exists?(path) do
    File.exists?(path)
  end

  # Private helpers

  defp parse_line(line) do
    case JSON.decode(line) do
      {:ok, entry} -> entry
      {:error, _} -> nil
    end
  end
end
