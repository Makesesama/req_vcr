defmodule Mix.Tasks.ReqVcr.Rename do
  @moduledoc """
  Rename or move cassette files.

  This task helps reorganize cassettes or migrate them when refactoring tests.

  ## Usage

      # Rename a single cassette
      mix req_vcr.rename old_name.jsonl new_name.jsonl

      # Move cassettes to a new directory structure
      mix req_vcr.rename --from "OldModule/" --to "NewModule/"

      # Migrate cassettes (for future schema changes)
      mix req_vcr.rename --migrate

  ## Options

    * `--from PREFIX` - Match cassettes starting with this prefix
    * `--to PREFIX` - Replace prefix with this value
    * `--dry-run` - Show what would be renamed without actually renaming
    * `--dir PATH` - Cassette directory (default: test/support/cassettes)
    * `--force` - Skip confirmation prompt
    * `--migrate` - Migrate cassettes to latest schema version (future use)
  """

  use Mix.Task

  @shortdoc "Rename or move cassette files"

  @cassette_dir "test/support/cassettes"

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          from: :string,
          to: :string,
          dry_run: :boolean,
          dir: :string,
          force: :boolean,
          migrate: :boolean
        ]
      )

    cassette_dir = opts[:dir] || @cassette_dir

    unless File.dir?(cassette_dir) do
      Mix.Shell.IO.error("Cassette directory not found: #{cassette_dir}")
      exit({:shutdown, 1})
    end

    cond do
      opts[:migrate] ->
        run_migration(cassette_dir, opts)

      opts[:from] && opts[:to] ->
        run_prefix_rename(cassette_dir, opts[:from], opts[:to], opts)

      length(positional) == 2 ->
        [from, to] = positional
        run_single_rename(cassette_dir, from, to, opts)

      true ->
        Mix.Shell.IO.error("Usage: mix req_vcr.rename <from> <to> OR --from PREFIX --to PREFIX")

        exit({:shutdown, 1})
    end
  end

  defp run_single_rename(dir, from, to, opts) do
    from_path = Path.join(dir, from)
    to_path = Path.join(dir, to)

    unless File.exists?(from_path) do
      Mix.Shell.IO.error("Source cassette not found: #{from_path}")
      exit({:shutdown, 1})
    end

    if File.exists?(to_path) and not opts[:force] do
      Mix.Shell.IO.error("Destination already exists: #{to_path}")
      Mix.Shell.IO.error("Use --force to overwrite")
      exit({:shutdown, 1})
    end

    if opts[:dry_run] do
      Mix.Shell.IO.info("DRY RUN - Would rename:")
      Mix.Shell.IO.info("  #{from_path}")
      Mix.Shell.IO.info("  → #{to_path}")
    else
      # Ensure destination directory exists
      to_path |> Path.dirname() |> File.mkdir_p!()

      File.rename!(from_path, to_path)
      Mix.Shell.IO.info("✓ Renamed:")
      Mix.Shell.IO.info("  #{from_path}")
      Mix.Shell.IO.info("  → #{to_path}")
    end
  end

  defp run_prefix_rename(dir, from_prefix, to_prefix, opts) do
    cassettes = find_cassettes_with_prefix(dir, from_prefix)

    if Enum.empty?(cassettes) do
      Mix.Shell.IO.info("No cassettes found with prefix: #{from_prefix}")
      exit({:shutdown, 0})
    end

    renames =
      Enum.map(cassettes, fn path ->
        relative = Path.relative_to(path, dir)
        new_relative = String.replace_prefix(relative, from_prefix, to_prefix)
        new_path = Path.join(dir, new_relative)
        {path, new_path}
      end)

    Mix.Shell.IO.info("Found #{length(renames)} cassette(s) to rename:\n")

    Enum.each(renames, fn {from, to} ->
      Mix.Shell.IO.info("  #{Path.relative_to(from, dir)}")
      Mix.Shell.IO.info("  → #{Path.relative_to(to, dir)}\n")
    end)

    if opts[:dry_run] do
      Mix.Shell.IO.info("DRY RUN - No changes made")
    else
      if opts[:force] or Mix.Shell.IO.yes?("Continue with rename?") do
        Enum.each(renames, fn {from, to} ->
          # Ensure destination directory exists
          to |> Path.dirname() |> File.mkdir_p!()
          File.rename!(from, to)
        end)

        Mix.Shell.IO.info("\n✓ Renamed #{length(renames)} cassette(s)!")
      else
        Mix.Shell.IO.info("Rename cancelled.")
      end
    end
  end

  defp run_migration(dir, opts) do
    Mix.Shell.IO.info("Migrating cassettes in #{dir}...\n")

    cassettes = find_all_cassettes(dir)

    if Enum.empty?(cassettes) do
      Mix.Shell.IO.info("No cassettes found.")
      exit({:shutdown, 0})
    end

    # Currently, we don't have schema versions, but this is a placeholder
    # for future migrations when the cassette format changes
    migrated =
      Enum.map(cassettes, fn path ->
        entries = load_cassette(path)
        migrated_entries = migrate_entries(entries)
        {path, entries != migrated_entries, migrated_entries}
      end)

    needs_migration = Enum.filter(migrated, fn {_path, changed, _entries} -> changed end)

    if Enum.empty?(needs_migration) do
      Mix.Shell.IO.info("✓ All cassettes are up to date!")
      exit({:shutdown, 0})
    end

    Mix.Shell.IO.info("#{length(needs_migration)} cassette(s) need migration:\n")

    Enum.each(needs_migration, fn {path, _, _} ->
      Mix.Shell.IO.info("  #{path}")
    end)

    if opts[:dry_run] do
      Mix.Shell.IO.info("\nDRY RUN - No changes made")
    else
      if opts[:force] or Mix.Shell.IO.yes?("\nContinue with migration?") do
        Enum.each(needs_migration, fn {path, _, entries} ->
          write_cassette(path, entries)
        end)

        Mix.Shell.IO.info("\n✓ Migrated #{length(needs_migration)} cassette(s)!")
      else
        Mix.Shell.IO.info("Migration cancelled.")
      end
    end
  end

  defp find_cassettes_with_prefix(dir, prefix) do
    Path.join(dir, prefix <> "**/*.jsonl")
    |> Path.wildcard()
  end

  defp find_all_cassettes(dir) do
    Path.join(dir, "**/*.jsonl")
    |> Path.wildcard()
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

  defp migrate_entries(entries) do
    # Placeholder for future schema migrations
    # For now, just return entries unchanged
    entries
  end

  defp write_cassette(path, entries) do
    content = Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
    File.write!(path, content)
  end
end
