defmodule Reqord.ContentAnalyzerTest do
  use ExUnit.Case
  doctest Reqord.ContentAnalyzer

  alias Reqord.ContentAnalyzer

  describe "analyze_content/2" do
    test "detects text content from content-type" do
      assert {:text, "hello"} = ContentAnalyzer.analyze_content("application/json", "hello")
      assert {:text, "world"} = ContentAnalyzer.analyze_content("text/plain", "world")
      assert {:text, "<html>"} = ContentAnalyzer.analyze_content("text/html", "<html>")
    end

    test "detects binary content from content-type" do
      # PNG header
      binary_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      assert {:binary, ^binary_data} = ContentAnalyzer.analyze_content("image/png", binary_data)
      assert {:binary, "video data"} = ContentAnalyzer.analyze_content("video/mp4", "video data")

      assert {:binary, "pdf data"} =
               ContentAnalyzer.analyze_content("application/pdf", "pdf data")
    end

    test "detects streaming content from content-type" do
      sse_data = "data: hello\n\n"
      assert {:stream, ^sse_data} = ContentAnalyzer.analyze_content("text/event-stream", sse_data)
    end

    test "falls back to heuristic analysis for unknown content-types" do
      # Text-like content
      assert {:text, "regular text"} = ContentAnalyzer.analyze_content(nil, "regular text")
      json_data = ~s({"key": "value"})
      assert {:text, ^json_data} = ContentAnalyzer.analyze_content("unknown/type", json_data)

      # Binary-like content (with null bytes)
      binary_with_nulls = "text with null\0byte"

      assert {:binary, ^binary_with_nulls} =
               ContentAnalyzer.analyze_content(nil, binary_with_nulls)
    end
  end

  describe "should_store_externally?/2" do
    test "recommends external storage for large binary content" do
      # Set a small threshold for testing
      Application.put_env(:reqord, :max_inline_size, 100)

      assert ContentAnalyzer.should_store_externally?(:binary, 200) == true
      assert ContentAnalyzer.should_store_externally?(:binary, 50) == false
      assert ContentAnalyzer.should_store_externally?(:stream, 200) == true
      assert ContentAnalyzer.should_store_externally?(:text, 200) == false

      # Cleanup
      Application.delete_env(:reqord, :max_inline_size)
    end
  end

  describe "extract_content_type/1" do
    test "extracts content-type from headers map" do
      headers = %{"content-type" => "application/json; charset=utf-8"}
      assert ContentAnalyzer.extract_content_type(headers) == "application/json"

      headers = %{"Content-Type" => "image/png"}
      assert ContentAnalyzer.extract_content_type(headers) == "image/png"
    end

    test "extracts content-type from headers list" do
      headers = [{"content-type", "text/plain"}, {"other", "value"}]
      assert ContentAnalyzer.extract_content_type(headers) == "text/plain"
    end

    test "returns nil for missing content-type" do
      assert ContentAnalyzer.extract_content_type(%{}) == nil
      assert ContentAnalyzer.extract_content_type([]) == nil
      assert ContentAnalyzer.extract_content_type("invalid") == nil
    end
  end
end
