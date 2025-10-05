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
end
