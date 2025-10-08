defmodule Mix.Tasks.Reqord.Edit do
  @moduledoc """
  Edit cassette entries in your editor with automatic JSON encoding/decoding.

  This task opens cassette entries in your configured editor (via $EDITOR or $VISUAL),
  handles JSONL parsing and formatting, and validates changes before saving.

  Useful for manually redacting sensitive data like emails, account IDs, or
  other PII from response bodies.

  ## Usage

      # Edit all entries in a cassette (relative to cassette dir)
      mix reqord.edit my_test.jsonl

      # Edit with full/relative path
      mix reqord.edit test/support/cassettes/auth_param_test.jsonl

      # Edit a specific entry by index (0-based)
      mix reqord.edit my_test.jsonl --entry 0

      # Edit entries matching a URL pattern
      mix reqord.edit my_test.jsonl --grep "/users"

      # Use a specific cassette directory (for short names only)
      mix reqord.edit my_test.jsonl --dir test/fixtures

  ## Options

    * `--entry INDEX` - Edit only the entry at INDEX (0-based)
    * `--grep PATTERN` - Edit only entries matching URL pattern
    * `--dir PATH` - Cassette directory (default: test/support/cassettes)

  ## Workflow

  1. Task loads cassette entries from JSONL file
  2. Filters entries based on --entry or --grep if specified
  3. Formats entries as pretty-printed JSON
  4. Opens your editor with the JSON content
  5. Validates JSON after you save and close the editor
  6. Writes valid entries back to the cassette file

  ## Editor Configuration

  The task uses your configured editor in this order:
  1. $VISUAL environment variable
  2. $EDITOR environment variable
  3. Falls back to 'vim' if neither is set

  ## Example: Redacting Emails

      # Edit the cassette
      mix reqord.edit AccountTest/fetches_user.jsonl

      # In your editor, find the response body and change:
      # "email": "user@example.com"
      # to:
      # "email": "[REDACTED]"

      # Save and close - the task validates and writes back to JSONL

  ## Error Handling

  - If JSON is invalid after editing, the task shows errors and exits without saving
  - Original cassette is preserved if validation fails
  - Use `mix reqord.show` to verify changes after editing
  """

  use Mix.Task

  @shortdoc "Edit cassette entries in your editor"

  @cassette_dir "test/support/cassettes"

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          entry: :integer,
          grep: :string,
          dir: :string
        ]
      )

    case positional do
      [cassette_name] ->
        edit_cassette(cassette_name, opts)

      [] ->
        Mix.Shell.IO.error("Usage: mix reqord.edit <cassette>")
        exit({:shutdown, 1})

      _ ->
        Mix.Shell.IO.error("Too many arguments. Usage: mix reqord.edit <cassette>")
        exit({:shutdown, 1})
    end
  end

  defp edit_cassette(name, opts) do
    # Handle both relative and absolute paths
    path =
      if Path.absname(name) == name or File.exists?(name) do
        # Already absolute path or exists as-is
        name
      else
        # Relative to cassette dir
        cassette_dir = opts[:dir] || @cassette_dir
        Path.join(cassette_dir, name)
      end

    unless File.exists?(path) do
      Mix.Shell.IO.error("Cassette not found: #{path}")
      exit({:shutdown, 1})
    end

    # Load and parse entries
    entries = load_entries(path)

    if entries == [] do
      Mix.Shell.IO.info("Cassette is empty: #{path}")
      exit({:shutdown, 0})
    end

    # Filter entries if needed
    filtered_entries = filter_entries(entries, opts)

    if filtered_entries == [] do
      Mix.Shell.IO.info("No entries match the filter criteria")
      exit({:shutdown, 0})
    end

    # Show what we're editing
    count = length(filtered_entries)
    total = length(entries)

    if count == total do
      Mix.Shell.IO.info("Editing all #{count} entries from #{path}")
    else
      Mix.Shell.IO.info("Editing #{count} of #{total} entries from #{path}")
    end

    # Format as pretty JSON for editing
    json_content = format_entries_for_editing(filtered_entries)

    # Open editor
    edited_content = open_in_editor(json_content)

    # Parse edited content
    case parse_edited_content(edited_content) do
      {:ok, edited_entries} ->
        # Validate entry count
        if length(edited_entries) != length(filtered_entries) do
          Mix.Shell.IO.error(
            "Entry count mismatch: started with #{length(filtered_entries)}, got #{length(edited_entries)}"
          )

          exit({:shutdown, 1})
        end

        # Replace edited entries in original list
        updated_entries = replace_entries(entries, filtered_entries, edited_entries, opts)

        # Write back to file
        write_entries(path, updated_entries)

        Mix.Shell.IO.info("✓ Successfully updated #{count} entries in #{path}")

      {:error, reason} ->
        Mix.Shell.IO.error("Failed to parse edited content: #{reason}")
        Mix.Shell.IO.error("Cassette was not modified")
        exit({:shutdown, 1})
    end
  end

  defp load_entries(path) do
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

  defp filter_entries(entries, opts) do
    entries
    |> filter_by_index(opts[:entry])
    |> filter_by_grep(opts[:grep])
  end

  defp filter_by_index(entries, nil), do: entries

  defp filter_by_index(entries, index) do
    case Enum.at(entries, index) do
      nil -> []
      entry -> [entry]
    end
  end

  defp filter_by_grep(entries, nil), do: entries

  defp filter_by_grep(entries, pattern) do
    Enum.filter(entries, fn entry ->
      url = get_in(entry, ["req", "url"]) || ""
      String.contains?(url, pattern)
    end)
  end

  defp format_entries_for_editing(entries) do
    entries
    |> Enum.map(&Jason.encode!(&1, pretty: true))
    |> Enum.join("\n---\n")
    |> Kernel.<>("\n")
  end

  defp open_in_editor(content) do
    editor = System.get_env("VISUAL") || System.get_env("EDITOR") || "vim"

    # Create temp file
    temp_file = Path.join(System.tmp_dir!(), "reqord_edit_#{:rand.uniform(999_999)}.json")

    try do
      File.write!(temp_file, content)

      # Open editor
      case System.cmd(editor, [temp_file], into: IO.stream(:stdio, :line)) do
        {_, 0} ->
          File.read!(temp_file)

        {_, exit_code} ->
          Mix.Shell.IO.error("Editor exited with code #{exit_code}")
          exit({:shutdown, 1})
      end
    after
      File.rm(temp_file)
    end
  end

  defp parse_edited_content(content) do
    # Split by separator and parse each entry
    entries =
      content
      |> String.split("---")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn entry_json ->
        case Jason.decode(entry_json) do
          {:ok, entry} -> validate_entry_structure(entry)
          {:error, error} -> {:error, "Invalid JSON: #{inspect(error)}"}
        end
      end)

    # Check for any errors
    case Enum.find(entries, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(entries, fn {:ok, entry} -> entry end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_entry_structure(entry) do
    cond do
      not is_map(entry) ->
        {:error, "Entry must be a JSON object"}

      not Map.has_key?(entry, "req") ->
        {:error, "Entry missing 'req' field"}

      not Map.has_key?(entry, "resp") ->
        {:error, "Entry missing 'resp' field"}

      not is_map(entry["req"]) ->
        {:error, "'req' must be an object"}

      not is_map(entry["resp"]) ->
        {:error, "'resp' must be an object"}

      not Map.has_key?(entry["req"], "url") ->
        {:error, "'req' missing 'url' field"}

      not Map.has_key?(entry["req"], "method") ->
        {:error, "'req' missing 'method' field"}

      not Map.has_key?(entry["resp"], "status") ->
        {:error, "'resp' missing 'status' field"}

      true ->
        {:ok, entry}
    end
  end

  defp replace_entries(all_entries, filtered_entries, edited_entries, _opts) do
    # Build a map of filtered entries for quick lookup
    filtered_set =
      filtered_entries
      |> Enum.with_index()
      |> Map.new(fn {entry, idx} -> {entry_key(entry), idx} end)

    # Replace entries in original list
    all_entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, _original_idx} ->
      key = entry_key(entry)

      case Map.get(filtered_set, key) do
        nil ->
          # Not filtered, keep original
          entry

        filtered_idx ->
          # Was filtered, use edited version
          Enum.at(edited_entries, filtered_idx)
      end
    end)
  end

  # Create a unique key for an entry to match it after editing
  defp entry_key(entry) do
    # Use URL + method + recorded_at for unique identification
    url = get_in(entry, ["req", "url"]) || ""
    method = get_in(entry, ["req", "method"]) || ""
    recorded_at = entry["recorded_at"] || ""
    "#{method}:#{url}:#{recorded_at}"
  end

  defp write_entries(path, entries) do
    content =
      entries
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(path, content)
  end
end
