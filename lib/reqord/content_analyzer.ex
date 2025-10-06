defmodule Reqord.ContentAnalyzer do
  @moduledoc """
  Analyzes HTTP response content to determine optimal storage strategy.

  This module provides utilities for:
  - Detecting binary vs text content
  - Determining appropriate encoding strategies
  - Identifying streaming responses
  """

  @binary_content_types ~w[
    image/
    video/
    audio/
    application/pdf
    application/zip
    application/gzip
    application/x-tar
    application/octet-stream
    application/msword
    application/vnd.openxmlformats-officedocument
    application/vnd.ms-excel
    application/vnd.ms-powerpoint
    font/
  ]

  @streaming_content_types ~w[
    text/event-stream
    application/x-ndjson
    application/stream+json
  ]

  @text_content_types ~w[
    text/
    application/json
    application/xml
    application/javascript
    application/x-www-form-urlencoded
    application/graphql
  ]

  @doc """
  Analyzes response content and returns encoding recommendation.

  ## Returns
  - `{:text, content}` - Text content, use Base64 encoding
  - `{:binary, content}` - Binary content, consider external storage
  - `{:stream, content}` - Streaming content, requires special handling

  ## Examples

      iex> Reqord.ContentAnalyzer.analyze_content("application/json", ~s({"key": "value"}))
      {:text, ~s({"key": "value"})}

      iex> Reqord.ContentAnalyzer.analyze_content("image/png", <<137, 80, 78, 71>>)
      {:binary, <<137, 80, 78, 71>>}

      iex> Reqord.ContentAnalyzer.analyze_content("text/event-stream", "data: chunk1\\n\\n")
      {:stream, "data: chunk1\\n\\n"}
  """
  @spec analyze_content(String.t() | nil, binary()) :: {:text | :binary | :stream, binary()}
  def analyze_content(content_type, content) when is_binary(content) do
    content_type = content_type || ""

    cond do
      streaming_content?(content_type) ->
        {:stream, content}

      binary_content_type?(content_type) ->
        {:binary, content}

      text_content_type?(content_type) ->
        {:text, content}

      true ->
        if appears_binary?(content) do
          {:binary, content}
        else
          {:text, content}
        end
    end
  end

  @doc """
  Determines if content should be stored externally based on size and type.

  ## Examples

      iex> Reqord.ContentAnalyzer.should_store_externally?(:binary, 2_000_000)
      true

      iex> Reqord.ContentAnalyzer.should_store_externally?(:text, 500_000)
      false
  """
  @spec should_store_externally?(atom(), non_neg_integer()) :: boolean()
  def should_store_externally?(content_type, size) do
    max_inline_size = Application.get_env(:reqord, :max_inline_size, 1_048_576)

    case content_type do
      :binary -> size > max_inline_size
      :stream -> size > max_inline_size
      :text -> false
    end
  end

  @doc """
  Extracts content-type from headers map or list.

  ## Examples

      iex> Reqord.ContentAnalyzer.extract_content_type(%{"content-type" => "application/json"})
      "application/json"

      iex> Reqord.ContentAnalyzer.extract_content_type([{"Content-Type", "image/png; charset=utf-8"}])
      "image/png"
  """
  @spec extract_content_type(map() | list()) :: String.t() | nil
  def extract_content_type(headers) when is_map(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(key) == "content-type" do
        extract_media_type(value)
      end
    end)
  end

  def extract_content_type(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(key) == "content-type" do
        extract_media_type(value)
      end
    end)
  end

  def extract_content_type(_), do: nil

  # Private functions

  defp binary_content_type?(content_type) do
    Enum.any?(@binary_content_types, &String.starts_with?(content_type, &1))
  end

  defp text_content_type?(content_type) do
    Enum.any?(@text_content_types, &String.starts_with?(content_type, &1))
  end

  defp streaming_content?(content_type) do
    Enum.any?(@streaming_content_types, &String.starts_with?(content_type, &1))
  end

  defp appears_binary?(content) when byte_size(content) == 0, do: false

  defp appears_binary?(content) do
    String.contains?(content, <<0>>) or
      has_high_entropy?(content)
  end

  defp has_high_entropy?(content) when byte_size(content) < 100, do: false

  defp has_high_entropy?(content) do
    sample_size = min(1000, byte_size(content))
    sample = :binary.part(content, 0, sample_size)

    non_printable_count =
      sample
      |> :binary.bin_to_list()
      |> Enum.count(fn byte -> byte < 32 or byte > 126 end)

    non_printable_count / sample_size > 0.3
  end

  defp extract_media_type(content_type) when is_binary(content_type) do
    content_type
    |> String.split(";")
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp extract_media_type(content_type) when is_list(content_type) do
    content_type
    |> List.first()
    |> extract_media_type()
  end
end
