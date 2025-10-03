defmodule Reqord.Cassette do
  @moduledoc """
  Handles cassette file operations including loading, saving, and validation.

  This module provides a clean interface for working with JSONL cassette files,
  handling errors gracefully and providing detailed logging for debugging.
  """

  require Logger

  alias Reqord.CassetteEntry

  @type cassette_path :: String.t()

  @doc """
  Loads entries from a cassette file.

  Returns a list of valid entries, skipping any malformed JSON lines
  and logging warnings for debugging.

  ## Examples

      iex> Reqord.Cassette.load("test/cassettes/example.jsonl")
      [%{"req" => %{...}, "resp" => %{...}}]

      iex> Reqord.Cassette.load("nonexistent.jsonl")
      []
  """
  @spec load(cassette_path()) :: [CassetteEntry.t()]
  def load(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.with_index(1)
      |> Stream.map(&decode_line/1)
      |> Stream.reject(&is_nil/1)
      |> Enum.to_list()
    else
      []
    end
  end

  @doc """
  Appends a single entry to a cassette file.

  Creates the directory structure if it doesn't exist.

  ## Examples

      Reqord.Cassette.append("test/cassettes/example.jsonl", entry)
  """
  @spec append(cassette_path(), CassetteEntry.t()) :: :ok
  def append(path, entry) do
    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Convert struct to map and encode
    entry_map = CassetteEntry.to_map(entry)
    encoded_entry = Reqord.JSON.encode!(entry_map)
    File.write!(path, encoded_entry <> "\n", [:append])
    :ok
  end

  @doc """
  Replaces the contents of a cassette file with a single entry.

  This is used for :all mode where the cassette should be completely rewritten.
  Creates the directory structure if it doesn't exist.

  ## Examples

      Reqord.Cassette.replace("test/cassettes/example.jsonl", entry)
  """
  @spec replace(cassette_path(), CassetteEntry.t()) :: :ok
  def replace(path, entry) do
    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Convert struct to map and encode
    entry_map = CassetteEntry.to_map(entry)
    encoded_entry = Reqord.JSON.encode!(entry_map)
    File.write!(path, encoded_entry <> "\n")
    :ok
  end

  @doc """
  Validates that a raw map can be converted to a CassetteEntry.

  Returns `{:ok, entry}` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_entry(map()) :: {:ok, CassetteEntry.t()} | {:error, String.t()}
  def validate_entry(raw_entry) when is_map(raw_entry) do
    case CassetteEntry.from_raw(raw_entry) do
      {:ok, entry} ->
        CassetteEntry.validate(entry)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_entry(_), do: {:error, "Entry must be a map"}

  # Private functions

  # Decode a single line with error handling and line number context
  defp decode_line({line, line_number}) do
    case Reqord.JSON.decode(line) do
      {:ok, raw_entry} ->
        case validate_entry(raw_entry) do
          {:ok, cassette_entry} ->
            cassette_entry

          {:error, reason} ->
            Logger.warning("Skipping invalid cassette entry at line #{line_number}: #{reason}")
            nil
        end

      {:error, error} ->
        Logger.warning(
          "Skipping malformed JSON at line #{line_number}: #{Exception.message(error)}"
        )

        nil
    end
  end
end
