defmodule Reqord.Storage.Behavior do
  @moduledoc """
  Behavior for storage backends.

  This module defines the interface that all storage backends must implement,
  allowing for pluggable storage solutions (FileSystem, S3, Redis, etc.).
  """

  @doc """
  Write a single entry to the specified cassette path.

  ## Parameters
    - `path` - The cassette path/identifier
    - `entry` - The entry data as a map

  ## Returns
    - `:ok` on success
    - `{:error, reason}` on failure
  """
  @callback write_entry(path :: String.t(), entry :: map()) :: :ok | {:error, term()}

  @doc """
  Stream all entries from the specified cassette path.

  ## Parameters
    - `path` - The cassette path/identifier

  ## Returns
    - An Enumerable that yields entry maps
  """
  @callback read_entries(path :: String.t()) :: Enumerable.t()

  @doc """
  Delete an entire cassette file.

  ## Parameters
    - `path` - The cassette path/identifier

  ## Returns
    - `:ok` on success (also returns :ok if file doesn't exist)
    - `{:error, reason}` on failure
  """
  @callback delete_cassette(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Ensure the path directory structure exists.

  ## Parameters
    - `path` - The cassette path whose directory structure should exist

  ## Returns
    - `:ok` on success
    - `{:error, reason}` on failure
  """
  @callback ensure_path_exists(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Check if a cassette exists at the specified path.

  ## Parameters
    - `path` - The cassette path/identifier

  ## Returns
    - `true` if the cassette exists
    - `false` otherwise
  """
  @callback exists?(path :: String.t()) :: boolean()

  @doc """
  Store a binary object externally and return its reference.

  ## Parameters
    - `hash` - Content hash to use as the object identifier
    - `content` - Binary content to store

  ## Returns
    - `{:ok, hash}` on success with the object hash
    - `{:error, reason}` on failure
  """
  @callback store_object(hash :: String.t(), content :: binary()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Load a binary object by its hash reference.

  ## Parameters
    - `hash` - Object hash identifier

  ## Returns
    - `{:ok, content}` on success with the binary content
    - `{:error, reason}` on failure (e.g., object not found)
  """
  @callback load_object(hash :: String.t()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Store streaming data chunks externally.

  ## Parameters
    - `hash` - Content hash to use as the stream identifier
    - `chunks` - List of {timestamp, data} tuples representing stream chunks

  ## Returns
    - `{:ok, hash}` on success with the stream hash
    - `{:error, reason}` on failure
  """
  @callback store_stream(hash :: String.t(), chunks :: list()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Load streaming data chunks by hash reference.

  ## Parameters
    - `hash` - Stream hash identifier

  ## Returns
    - `{:ok, chunks}` on success with list of {timestamp, data} tuples
    - `{:error, reason}` on failure
  """
  @callback load_stream(hash :: String.t()) :: {:ok, list()} | {:error, term()}

  @doc """
  Delete an external object by its hash.

  ## Parameters
    - `hash` - Object hash identifier

  ## Returns
    - `:ok` on success (also returns :ok if object doesn't exist)
    - `{:error, reason}` on failure
  """
  @callback delete_object(hash :: String.t()) :: :ok | {:error, term()}

  @doc """
  List all stored objects (for maintenance tasks).

  ## Returns
    - `{:ok, hashes}` with list of object hash identifiers
    - `{:error, reason}` on failure
  """
  @callback list_objects() :: {:ok, [String.t()]} | {:error, term()}
end
