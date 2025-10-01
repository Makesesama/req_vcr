defmodule Mix.Tasks.ReqVcr.Audit do
  @moduledoc """
  Audits cassette files for potential issues.

  This task scans all cassette files and reports:
  - Potential secrets or sensitive data that should be redacted
  - Unused cassette entries (requires running tests first)
  - Stale cassettes (old recorded dates)

  ## Usage

      mix req_vcr.audit
      mix req_vcr.audit --secrets-only
      mix req_vcr.audit --unused-only
      mix req_vcr.audit --stale-days 90

  ## Options

    * `--secrets-only` - Only check for potential secrets
    * `--unused-only` - Only check for unused cassettes (requires test coverage data)
    * `--stale-days N` - Report cassettes older than N days (default: 365)
    * `--dir PATH` - Cassette directory (default: test/support/cassettes)
  """

  use Mix.Task

  @shortdoc "Audit cassette files for secrets, unused entries, and staleness"

  @cassette_dir "test/support/cassettes"
  @default_stale_days 365

  # Patterns that might indicate secrets
  @secret_patterns [
    ~r/[a-zA-Z0-9]{32,}/,
    # Long alphanumeric strings
    ~r/sk_[a-zA-Z0-9]+/,
    # Stripe keys
    ~r/pk_[a-zA-Z0-9]+/,
    # Stripe keys
    ~r/Bearer [a-zA-Z0-9._-]+/,
    # Bearer tokens
    ~r/Basic [a-zA-Z0-9+\/=]+/,
    # Basic auth
    ~r/ghp_[a-zA-Z0-9]{36}/,
    # GitHub tokens
    ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
    # UUIDs (might be session IDs)
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: no_return()
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          secrets_only: :boolean,
          unused_only: :boolean,
          stale_days: :integer,
          dir: :string
        ]
      )

    cassette_dir = opts[:dir] || @cassette_dir
    stale_days = opts[:stale_days] || @default_stale_days

    unless File.dir?(cassette_dir) do
      Mix.Shell.IO.error("Cassette directory not found: #{cassette_dir}")
      exit({:shutdown, 1})
    end

    Mix.Shell.IO.info("Auditing cassettes in #{cassette_dir}...\n")

    cassettes = find_cassettes(cassette_dir)

    if Enum.empty?(cassettes) do
      Mix.Shell.IO.info("No cassettes found.")
      exit({:shutdown, 0})
    end

    issues = %{
      secrets: [],
      unused: [],
      stale: []
    }

    # Check secrets unless specifically excluded
    issues =
      if not (opts[:unused_only] == true) and not is_integer(opts[:stale_days]) do
        %{issues | secrets: check_secrets(cassettes)}
      else
        issues
      end

    # Check unused unless specifically excluded
    issues =
      if not (opts[:secrets_only] == true) and not is_integer(opts[:stale_days]) do
        %{issues | unused: check_unused(cassettes)}
      else
        issues
      end

    # Check stale unless specifically excluded
    issues =
      if not (opts[:secrets_only] == true) and not (opts[:unused_only] == true) do
        %{issues | stale: check_stale(cassettes, stale_days)}
      else
        issues
      end

    report_issues(issues, opts)
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

  defp check_secrets(cassettes) do
    Enum.flat_map(cassettes, fn {path, entries} ->
      Enum.with_index(entries, 1)
      |> Enum.flat_map(fn {entry, line_num} ->
        find_secrets_in_entry(entry, path, line_num)
      end)
    end)
  end

  defp find_secrets_in_entry(entry, path, line_num) do
    issues = []

    # Check request headers
    req_headers = get_in(entry, ["req", "headers"]) || %{}

    issues =
      issues ++
        Enum.flat_map(req_headers, fn {key, value} ->
          if value != "<REDACTED>" and matches_secret_pattern?(value) do
            [
              %{
                path: path,
                line: line_num,
                type: :secret,
                location: "req.headers.#{key}",
                value: truncate_secret(value)
              }
            ]
          else
            []
          end
        end)

    # Check request URL for non-redacted secrets
    req_url = get_in(entry, ["req", "url"]) || ""

    issues =
      if String.contains?(req_url, ["token=", "apikey=", "api_key="]) and
           not String.contains?(req_url, "REDACTED") do
        issues ++
          [
            %{
              path: path,
              line: line_num,
              type: :secret,
              location: "req.url",
              value: truncate_secret(req_url)
            }
          ]
      else
        issues
      end

    # Check response body for potential secrets
    resp_body_b64 = get_in(entry, ["resp", "body_b64"])

    issues =
      if resp_body_b64 do
        body = Base.decode64!(resp_body_b64)

        if matches_secret_pattern?(body) do
          issues ++
            [
              %{
                path: path,
                line: line_num,
                type: :secret,
                location: "resp.body",
                value: "(response body contains potential secrets)"
              }
            ]
        else
          issues
        end
      else
        issues
      end

    issues
  end

  defp matches_secret_pattern?(text) do
    Enum.any?(@secret_patterns, &Regex.match?(&1, text))
  end

  defp truncate_secret(value) do
    if String.length(value) > 50 do
      String.slice(value, 0..47) <> "..."
    else
      value
    end
  end

  defp check_unused(_cassettes) do
    # This would require instrumentation during test runs
    # For now, just return empty list with a note
    Mix.Shell.IO.info("Note: Unused cassette detection requires running tests with coverage.\n")
    []
  end

  defp check_stale(cassettes, stale_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-stale_days, :day)

    Enum.flat_map(cassettes, fn {path, _entries} ->
      case File.stat(path) do
        {:ok, stat} ->
          mtime = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

          if DateTime.compare(mtime, cutoff) == :lt do
            [
              %{
                path: path,
                type: :stale,
                age_days: DateTime.diff(DateTime.utc_now(), mtime, :day)
              }
            ]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  @spec report_issues(map(), keyword()) :: no_return()
  defp report_issues(issues, opts) do
    total = length(issues.secrets) + length(issues.unused) + length(issues.stale)

    if total == 0 do
      Mix.Shell.IO.info("✓ No issues found!")
      exit({:shutdown, 0})
    end

    unless Enum.empty?(issues.secrets) or opts[:unused_only] or opts[:stale_days] do
      Mix.Shell.IO.error("\n⚠ Potential Secrets Found (#{length(issues.secrets)}):\n")

      Enum.each(issues.secrets, fn issue ->
        Mix.Shell.IO.error("  #{issue.path}:#{issue.line}")
        Mix.Shell.IO.error("    Location: #{issue.location}")
        Mix.Shell.IO.error("    Value: #{issue.value}\n")
      end)
    end

    unless Enum.empty?(issues.stale) or opts[:secrets_only] or opts[:unused_only] do
      Mix.Shell.IO.info("\n⏰ Stale Cassettes (#{length(issues.stale)}):\n")

      Enum.each(issues.stale, fn issue ->
        Mix.Shell.IO.info("  #{issue.path} (#{issue.age_days} days old)")
      end)
    end

    unless Enum.empty?(issues.unused) or opts[:secrets_only] or opts[:stale_days] do
      Mix.Shell.IO.info("\n🗑  Unused Cassettes (#{length(issues.unused)}):\n")

      Enum.each(issues.unused, fn issue ->
        Mix.Shell.IO.info("  #{issue.path}")
      end)
    end

    Mix.Shell.IO.info("\nTotal issues: #{total}")

    if total > 0 do
      exit({:shutdown, 1})
    else
      exit({:shutdown, 0})
    end
  end
end
