defmodule Reqord.Tasks.Helpers do
  @moduledoc """
  Shared helper functions for Reqord Mix tasks.

  Provides common utilities for:
  - Resolving cassette paths (relative, absolute, short names)
  - Loading and parsing cassette entries
  - Finding cassettes in directories
  """

  @default_cassette_dir "test/support/cassettes"

  @doc """
  Resolves a cassette path, handling both short names and full paths.

  ## Examples

      # Short name (relative to cassette dir)
      resolve_cassette_path("my_test.jsonl", [])
      #=> "test/support/cassettes/my_test.jsonl"

      # Relative path from project root
      resolve_cassette_path("test/support/cassettes/my_test.jsonl", [])
      #=> "test/support/cassettes/my_test.jsonl"

      # Absolute path
      resolve_cassette_path("/full/path/to/cassette.jsonl", [])
      #=> "/full/path/to/cassette.jsonl"

      # Custom cassette directory
      resolve_cassette_path("my_test.jsonl", dir: "test/fixtures")
      #=> "test/fixtures/my_test.jsonl"

  """
  @spec resolve_cassette_path(String.t(), keyword()) :: String.t()
  def resolve_cassette_path(name, opts) do
    if Path.absname(name) == name or File.exists?(name) do
      # Already absolute path or exists as-is
      name
    else
      # Relative to cassette dir
      cassette_dir = opts[:dir] || @default_cassette_dir
      Path.join(cassette_dir, name)
    end
  end

  @doc """
  Loads and parses entries from a cassette file.

  Returns a list of decoded JSON entries.

  ## Examples

      load_entries("test/support/cassettes/my_test.jsonl")
      #=> [%{"req" => %{...}, "resp" => %{...}}]

  """
  @spec load_entries(String.t()) :: [map()]
  def load_entries(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, entry} -> entry
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Finds all cassette files in a directory recursively.

  Returns a list of absolute paths to .jsonl files.

  ## Examples

      find_cassettes("test/support/cassettes")
      #=> [
        "test/support/cassettes/my_test.jsonl",
        "test/support/cassettes/api/users_test.jsonl"
      ]

  """
  @spec find_cassettes(String.t()) :: [String.t()]
  def find_cassettes(dir) do
    Path.join(dir, "**/*.jsonl")
    |> Path.wildcard()
    |> Enum.sort()
  end

  @doc """
  Validates that a cassette file exists.

  Exits with error message if file doesn't exist.

  ## Examples

      ensure_cassette_exists!("test/support/cassettes/my_test.jsonl")
      #=> :ok

      ensure_cassette_exists!("nonexistent.jsonl")
      #=> exits with error

  """
  @spec ensure_cassette_exists!(String.t()) :: :ok
  def ensure_cassette_exists!(path) do
    unless File.exists?(path) do
      Mix.Shell.IO.error("Cassette not found: #{path}")
      exit({:shutdown, 1})
    end

    :ok
  end

  @doc """
  Validates that a directory exists.

  Exits with error message if directory doesn't exist.

  ## Examples

      ensure_directory_exists!("test/support/cassettes")
      #=> :ok

      ensure_directory_exists!("nonexistent")
      #=> exits with error

  """
  @spec ensure_directory_exists!(String.t()) :: :ok
  def ensure_directory_exists!(dir) do
    unless File.dir?(dir) do
      Mix.Shell.IO.error("Directory not found: #{dir}")
      exit({:shutdown, 1})
    end

    :ok
  end

  @doc """
  Gets the default cassette directory.

  ## Examples

      default_cassette_dir()
      #=> "test/support/cassettes"

  """
  @spec default_cassette_dir() :: String.t()
  def default_cassette_dir, do: @default_cassette_dir

  @doc """
  Writes entries back to a cassette file.

  Each entry is encoded as JSON and written on a single line.

  ## Examples

      write_entries("cassette.jsonl", [
        %{"req" => %{...}, "resp" => %{...}}
      ])
      #=> :ok

  """
  @spec write_entries(String.t(), [map()]) :: :ok
  def write_entries(path, entries) do
    content =
      entries
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(path, content)
  end
end
