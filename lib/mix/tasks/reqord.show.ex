defmodule Mix.Tasks.Reqord.Show do
  @moduledoc """
  Display cassette contents in a readable format.

  This task helps inspect cassette files and their entries.

  ## Usage

      # Show all entries in a cassette (relative to cassette dir)
      mix reqord.show my_test.jsonl

      # Show with full/relative path
      mix reqord.show test/support/cassettes/auth_param_test.jsonl

      # Show entries matching a URL pattern
      mix reqord.show my_test.jsonl --grep "/users"

      # Show entries for a specific HTTP method
      mix reqord.show my_test.jsonl --method GET

      # Show only request details
      mix reqord.show my_test.jsonl --request-only

      # Show only response details
      mix reqord.show my_test.jsonl --response-only

      # Show raw JSON
      mix reqord.show my_test.jsonl --raw

  ## Options

    * `--grep PATTERN` - Filter entries by URL pattern
    * `--method METHOD` - Filter by HTTP method (GET, POST, etc.)
    * `--request-only` - Only show request details
    * `--response-only` - Only show response details
    * `--raw` - Show raw JSON instead of formatted output
    * `--decode-body` - Decode and pretty-print response bodies
    * `--dir PATH` - Cassette directory (default: test/support/cassettes)
  """

  use Mix.Task

  alias Reqord.Tasks.Helpers

  @shortdoc "Display cassette contents"

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          grep: :string,
          method: :string,
          request_only: :boolean,
          response_only: :boolean,
          raw: :boolean,
          decode_body: :boolean,
          dir: :string
        ]
      )

    case positional do
      [cassette_name] ->
        show_cassette(cassette_name, opts)

      [] ->
        Mix.Shell.IO.error("Usage: mix reqord.show <cassette>")
        exit({:shutdown, 1})

      _ ->
        Mix.Shell.IO.error("Too many arguments. Usage: mix reqord.show <cassette>")
        exit({:shutdown, 1})
    end
  end

  defp show_cassette(name, opts) do
    path = Helpers.resolve_cassette_path(name, opts)
    Helpers.ensure_cassette_exists!(path)

    entries = Helpers.load_entries(path)

    if Enum.empty?(entries) do
      Mix.Shell.IO.info("Cassette is empty: #{path}")
      exit({:shutdown, 0})
    end

    # Apply filters
    filtered_entries = filter_entries(entries, opts)

    if Enum.empty?(filtered_entries) do
      Mix.Shell.IO.info("No entries match the filters.")
      exit({:shutdown, 0})
    end

    Mix.Shell.IO.info("Cassette: #{path}")
    Mix.Shell.IO.info("Entries: #{length(filtered_entries)}/#{length(entries)}\n")

    if opts[:raw] do
      show_raw(filtered_entries)
    else
      show_formatted(filtered_entries, opts)
    end
  end

  defp filter_entries(entries, opts) do
    entries
    |> filter_by_url(opts[:grep])
    |> filter_by_method(opts[:method])
  end

  defp filter_by_url(entries, nil), do: entries

  defp filter_by_url(entries, pattern) do
    Enum.filter(entries, fn entry ->
      url = get_in(entry, ["req", "url"]) || ""
      String.contains?(url, pattern)
    end)
  end

  defp filter_by_method(entries, nil), do: entries

  defp filter_by_method(entries, method) do
    method_upper = String.upcase(method)

    Enum.filter(entries, fn entry ->
      entry_method = get_in(entry, ["req", "method"]) || ""
      String.upcase(entry_method) == method_upper
    end)
  end

  defp show_raw(entries) do
    Enum.each(entries, fn entry ->
      Mix.Shell.IO.info(Reqord.JSON.encode!(entry))
      Mix.Shell.IO.info("")
    end)
  end

  defp show_formatted(entries, opts) do
    Enum.with_index(entries, 1)
    |> Enum.each(fn {entry, idx} ->
      Mix.Shell.IO.info("═══ Entry #{idx} ═══")
      Mix.Shell.IO.info("Key: #{entry["key"]}\n")

      unless opts[:response_only] do
        show_request(entry["req"], opts)
      end

      unless opts[:request_only] do
        show_response(entry["resp"], opts)
      end

      Mix.Shell.IO.info("")
    end)
  end

  defp show_request(req, _opts) do
    Mix.Shell.IO.info("┌─ Request")
    Mix.Shell.IO.info("│ Method: #{req["method"]}")
    Mix.Shell.IO.info("│ URL: #{req["url"]}")

    if req["body_hash"] != "-" do
      Mix.Shell.IO.info("│ Body Hash: #{req["body_hash"]}")
    end

    headers = req["headers"] || %{}

    unless Enum.empty?(headers) do
      Mix.Shell.IO.info("│ Headers:")

      Enum.each(headers, fn {key, value} ->
        Mix.Shell.IO.info("│   #{key}: #{value}")
      end)
    end

    Mix.Shell.IO.info("└─")
  end

  defp show_response(resp, opts) do
    Mix.Shell.IO.info("┌─ Response")
    Mix.Shell.IO.info("│ Status: #{resp["status"]}")

    headers = resp["headers"] || %{}

    unless Enum.empty?(headers) do
      Mix.Shell.IO.info("│ Headers:")

      Enum.each(headers, fn {key, value} ->
        Mix.Shell.IO.info("│   #{key}: #{value}")
      end)
    end

    if resp["body_b64"] do
      body = Base.decode64!(resp["body_b64"])
      body_preview = format_body(body, headers, opts)
      Mix.Shell.IO.info("│ Body (#{byte_size(body)} bytes):")

      body_preview
      |> String.split("\n")
      |> Enum.each(fn line ->
        Mix.Shell.IO.info("│   #{line}")
      end)
    end

    Mix.Shell.IO.info("└─")
  end

  defp format_body(body, headers, opts) do
    cond do
      opts[:decode_body] && json_content_type?(headers) ->
        try do
          body |> Reqord.JSON.decode!() |> Reqord.JSON.encode!()
        rescue
          _ -> truncate_body(body)
        end

      byte_size(body) > 500 ->
        truncate_body(body)

      true ->
        body
    end
  end

  defp json_content_type?(headers) do
    content_type = headers["content-type"] || headers["Content-Type"] || ""
    String.contains?(content_type, "json")
  end

  defp truncate_body(body) do
    if byte_size(body) > 500 do
      String.slice(body, 0..497) <> "..."
    else
      body
    end
  end
end
