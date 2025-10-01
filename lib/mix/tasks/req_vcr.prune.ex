defmodule Mix.Tasks.ReqVcr.Prune do
  @moduledoc """
  Removes unused cassette entries and files.

  This task helps clean up cassette files by removing:
  - Empty cassette files
  - Duplicate entries (same key)
  - Optionally, cassettes older than a specified age

  ## Usage

      mix req_vcr.prune
      mix req_vcr.prune --dry-run
      mix req_vcr.prune --stale-days 180
      mix req_vcr.prune --duplicates-only

  ## Options

    * `--dry-run` - Show what would be removed without actually removing
    * `--stale-days N` - Remove cassettes older than N days
    * `--duplicates-only` - Only remove duplicate entries within cassettes
    * `--empty-only` - Only remove empty cassette files
    * `--dir PATH` - Cassette directory (default: test/support/cassettes)
    * `--force` - Skip confirmation prompt
  """

  use Mix.Task

  @shortdoc "Remove unused cassette entries and files"

  @cassette_dir "test/support/cassettes"

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          dry_run: :boolean,
          stale_days: :integer,
          duplicates_only: :boolean,
          empty_only: :boolean,
          dir: :string,
          force: :boolean
        ]
      )

    cassette_dir = opts[:dir] || @cassette_dir

    unless File.dir?(cassette_dir) do
      Mix.Shell.IO.error("Cassette directory not found: #{cassette_dir}")
      exit({:shutdown, 1})
    end

    Mix.Shell.IO.info("Scanning cassettes in #{cassette_dir}...\n")

    actions = build_prune_actions(cassette_dir, opts)

    if Enum.empty?(actions) do
      Mix.Shell.IO.info("✓ Nothing to prune!")
      exit({:shutdown, 0})
    end

    report_actions(actions, opts)

    unless opts[:dry_run] do
      if opts[:force] or confirm_prune(actions) do
        execute_actions(actions, opts)
        Mix.Shell.IO.info("\n✓ Prune completed!")
      else
        Mix.Shell.IO.info("Prune cancelled.")
      end
    end
  end

  defp build_prune_actions(dir, opts) do
    cassettes = find_cassettes(dir)
    actions = []

    # Find empty cassettes
    actions =
      if not (opts[:duplicates_only] == true) and not is_integer(opts[:stale_days]) do
        actions ++ find_empty_cassettes(cassettes)
      else
        actions
      end

    # Find stale cassettes
    actions =
      if is_integer(opts[:stale_days]) do
        actions ++ find_stale_cassettes(cassettes, opts[:stale_days])
      else
        actions
      end

    # Find duplicates
    actions =
      if not (opts[:empty_only] == true) and not is_integer(opts[:stale_days]) do
        actions ++ find_duplicate_entries(cassettes)
      else
        actions
      end

    actions
  end

  defp find_cassettes(dir) do
    Path.join(dir, "**/*.jsonl")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {path, load_cassette(path)}
    end)
  end

  defp load_cassette(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode!/1)
    |> Enum.to_list()
  rescue
    _ -> []
  end

  defp find_empty_cassettes(cassettes) do
    Enum.flat_map(cassettes, fn {path, entries} ->
      if Enum.empty?(entries) do
        [%{type: :delete_file, path: path, reason: "empty cassette"}]
      else
        []
      end
    end)
  end

  defp find_stale_cassettes(cassettes, stale_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-stale_days, :day)

    Enum.flat_map(cassettes, fn {path, _entries} ->
      case File.stat(path) do
        {:ok, stat} ->
          mtime = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

          if DateTime.compare(mtime, cutoff) == :lt do
            age_days = DateTime.diff(DateTime.utc_now(), mtime, :day)
            [%{type: :delete_file, path: path, reason: "stale (#{age_days} days old)"}]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  defp find_duplicate_entries(cassettes) do
    Enum.flat_map(cassettes, fn {path, entries} ->
      # Group by key and find duplicates
      duplicates =
        entries
        |> Enum.with_index(1)
        |> Enum.group_by(fn {entry, _idx} -> entry["key"] end)
        |> Enum.filter(fn {_key, occurrences} -> length(occurrences) > 1 end)

      if Enum.empty?(duplicates) do
        []
      else
        dup_count = Enum.reduce(duplicates, 0, fn {_key, occs}, acc -> acc + length(occs) - 1 end)

        [
          %{
            type: :remove_duplicates,
            path: path,
            reason: "#{dup_count} duplicate entries",
            entries: entries
          }
        ]
      end
    end)
  end

  defp report_actions(actions, opts) do
    if opts[:dry_run] do
      Mix.Shell.IO.info("DRY RUN - No changes will be made\n")
    end

    delete_files = Enum.filter(actions, &(&1.type == :delete_file))
    dedup_files = Enum.filter(actions, &(&1.type == :remove_duplicates))

    unless Enum.empty?(delete_files) do
      Mix.Shell.IO.info("Files to delete (#{length(delete_files)}):\n")

      Enum.each(delete_files, fn action ->
        Mix.Shell.IO.info("  #{action.path}")
        Mix.Shell.IO.info("    Reason: #{action.reason}\n")
      end)
    end

    unless Enum.empty?(dedup_files) do
      Mix.Shell.IO.info("Files with duplicates to clean (#{length(dedup_files)}):\n")

      Enum.each(dedup_files, fn action ->
        Mix.Shell.IO.info("  #{action.path}")
        Mix.Shell.IO.info("    Reason: #{action.reason}\n")
      end)
    end
  end

  defp confirm_prune(actions) do
    delete_count = Enum.count(actions, &(&1.type == :delete_file))
    dedup_count = Enum.count(actions, &(&1.type == :remove_duplicates))

    Mix.Shell.IO.info("\nThis will:")

    if delete_count > 0 do
      Mix.Shell.IO.info("  - Delete #{delete_count} cassette file(s)")
    end

    if dedup_count > 0 do
      Mix.Shell.IO.info("  - Remove duplicates from #{dedup_count} cassette file(s)")
    end

    Mix.Shell.IO.yes?("\nContinue with prune?")
  end

  defp execute_actions(actions, _opts) do
    Enum.each(actions, fn action ->
      case action.type do
        :delete_file ->
          File.rm!(action.path)
          Mix.Shell.IO.info("Deleted: #{action.path}")

        :remove_duplicates ->
          deduplicated = deduplicate_entries(action.entries)
          write_cassette(action.path, deduplicated)
          Mix.Shell.IO.info("Deduplicated: #{action.path}")
      end
    end)
  end

  defp deduplicate_entries(entries) do
    # Keep the last occurrence of each key
    entries
    |> Enum.reverse()
    |> Enum.uniq_by(fn entry -> entry["key"] end)
    |> Enum.reverse()
  end

  defp write_cassette(path, entries) do
    content = Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
    File.write!(path, content)
  end
end
