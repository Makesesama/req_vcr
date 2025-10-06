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

  @doc """
  Store a binary object in the objects directory.
  """
  @impl true
  def store_object(hash, content) when is_binary(hash) and is_binary(content) do
    object_path = object_path(hash)

    case ensure_path_exists(object_path) do
      :ok ->
        case File.write(object_path, content) do
          :ok -> {:ok, hash}
          {:error, reason} -> {:error, "Failed to store object: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, "Object storage error: #{Exception.message(e)}"}
  end

  @doc """
  Load a binary object from the objects directory.
  """
  @impl true
  def load_object(hash) when is_binary(hash) do
    object_path = object_path(hash)

    case File.read(object_path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, "Failed to load object: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Object loading error: #{Exception.message(e)}"}
  end

  @doc """
  Store stream chunks in the streams directory.
  """
  @impl true
  def store_stream(hash, chunks) when is_binary(hash) and is_list(chunks) do
    stream_path = stream_path(hash)

    case ensure_path_exists(stream_path) do
      :ok ->
        # Encode chunks as JSON Lines format (newline-delimited JSON) for easy parsing
        content = Enum.map_join(chunks, "\n", &JSON.encode!/1)

        case File.write(stream_path, content) do
          :ok -> {:ok, hash}
          {:error, reason} -> {:error, "Failed to store stream: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, "Stream storage error: #{Exception.message(e)}"}
  end

  @doc """
  Load stream chunks from the streams directory.
  """
  @impl true
  def load_stream(hash) when is_binary(hash) do
    stream_path = stream_path(hash)

    case File.read(stream_path) do
      {:ok, content} ->
        chunks =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&decode_chunk_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, "Failed to load stream: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Stream loading error: #{Exception.message(e)}"}
  end

  @doc """
  Delete an external object.
  """
  @impl true
  def delete_object(hash) when is_binary(hash) do
    object_path = object_path(hash)
    stream_path = stream_path(hash)

    # Delete both object and stream files if they exist
    with :ok <- delete_file_if_exists(object_path),
         :ok <- delete_file_if_exists(stream_path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, "Object deletion error: #{Exception.message(e)}"}
  end

  @doc """
  List all stored objects.
  """
  @impl true
  def list_objects do
    objects_dir = objects_directory()

    case File.ls(objects_dir) do
      {:ok, files} ->
        # Filter out non-object files and return just the hashes
        objects =
          files
          |> Enum.filter(&String.match?(&1, ~r/^[a-f0-9]{64}$/))

        {:ok, objects}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, "Failed to list objects: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Object listing error: #{Exception.message(e)}"}
  end

  # Private helpers

  defp parse_line(line) do
    case JSON.decode(line) do
      {:ok, entry} -> entry
      {:error, _} -> nil
    end
  end

  # Object storage path helpers

  defp objects_directory do
    Reqord.Config.object_directory()
  end

  defp streams_directory do
    Path.join(Reqord.Config.object_directory(), "streams")
  end

  defp object_path(hash) do
    # Use first 2 chars as subdirectory for better file system performance
    subdir = String.slice(hash, 0, 2)
    Path.join([objects_directory(), subdir, hash])
  end

  defp stream_path(hash) do
    Path.join(streams_directory(), "#{hash}.json")
  end

  defp delete_file_if_exists(path) do
    case File.rm(path) do
      :ok -> :ok
      # File doesn't exist, that's fine
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, "Failed to delete #{path}: #{inspect(reason)}"}
    end
  end

  defp decode_chunk_line(line) do
    case JSON.decode(line) do
      {:ok, chunk} -> chunk
      {:error, _} -> nil
    end
  end
end
