defmodule ReqVCR.JSON.JasonTest do
  use ExUnit.Case
  import ReqVCR.TestHelpers

  @test_stub ReqVCR.JSON.JasonTest.Stub
  @cassette_dir "test/support/cassettes"

  setup do
    # Ensure cassette directory exists
    File.mkdir_p!(@cassette_dir)

    # Set up Req.Test
    Req.Test.set_req_test_to_private()
    Req.Test.set_req_test_from_context(%{async: true})

    # Clean up test cassettes after each test
    test_files = [
      "jason_adapter_basic.jsonl",
      "jason_adapter_complex.jsonl",
      "jason_adapter_integration.jsonl"
    ]

    on_exit(fn ->
      Enum.each(test_files, fn file ->
        file_path = Path.join(@cassette_dir, file)

        if File.exists?(file_path) do
          File.rm!(file_path)
        end
      end)
    end)

    :ok
  end

  describe "Jason adapter" do
    test "encodes and decodes basic data structures" do
      with_module_and_config(Jason, "Jason", :req_vcr, :json_library, ReqVCR.JSON.Jason, fn ->
        # Test basic data types
        test_cases = [
          %{"string" => "hello"},
          %{"number" => 42},
          %{"float" => 3.14},
          %{"boolean" => true},
          %{"null" => nil},
          %{"array" => [1, 2, 3]},
          %{"nested" => %{"key" => "value"}}
        ]

        Enum.each(test_cases, fn data ->
          encoded = ReqVCR.JSON.encode!(data)
          assert is_binary(encoded)

          {:ok, decoded} = ReqVCR.JSON.decode(encoded)
          assert decoded == data

          decoded! = ReqVCR.JSON.decode!(encoded)
          assert decoded! == data
        end)
      end)
    end

    test "handles encoding/decoding errors properly" do
      with_module_and_config(Jason, "Jason", :req_vcr, :json_library, ReqVCR.JSON.Jason, fn ->
        # Test invalid JSON decoding
        {:error, error} = ReqVCR.JSON.decode("invalid json {")
        assert is_struct(error, Jason.DecodeError)
        assert Exception.message(error) =~ "unexpected"

        # Test decode! with invalid JSON
        assert_raise Jason.DecodeError, fn ->
          ReqVCR.JSON.decode!("invalid json {")
        end

        # Test encoding edge cases
        valid_data = %{"message" => "valid"}
        encoded = ReqVCR.JSON.encode!(valid_data)
        {:ok, decoded} = ReqVCR.JSON.decode(encoded)
        assert decoded == valid_data
      end)
    end

    test "creates and loads real cassettes" do
      with_module_and_config(Jason, "Jason", :req_vcr, :json_library, ReqVCR.JSON.Jason, fn ->
        # Create a realistic cassette entry
        cassette_path = Path.join(@cassette_dir, "jason_adapter_integration.jsonl")

        api_response_data = %{
          "id" => 123,
          "name" => "John Doe",
          "email" => "john@example.com",
          "profile" => %{
            "age" => 30,
            "interests" => ["programming", "music", "travel"]
          },
          "created_at" => "2024-01-01T12:00:00Z"
        }

        test_entry = %{
          req: %{
            method: "GET",
            url: "https://api.example.com/users/123",
            headers: %{"accept" => "application/json", "authorization" => "<REDACTED>"},
            body_hash: "-"
          },
          resp: %{
            status: 200,
            headers: %{"content-type" => "application/json", "x-request-id" => "req-123"},
            body_b64: Base.encode64(Jason.encode!(api_response_data))
          }
        }

        # Write cassette using ReqVCR.JSON
        encoded = ReqVCR.JSON.encode!(test_entry)
        File.write!(cassette_path, encoded <> "\n")

        # Verify file was written correctly
        content = File.read!(cassette_path)
        assert String.contains?(content, "https://api.example.com/users/123")
        assert String.contains?(content, "body_b64")

        # Verify we can load it back
        {:ok, decoded} = ReqVCR.JSON.decode(String.trim(content))
        assert decoded["req"]["method"] == "GET"
        assert decoded["resp"]["status"] == 200

        # Test VCR integration
        ReqVCR.install!(
          name: @test_stub,
          cassette: "jason_adapter_integration",
          mode: :once
        )

        client = Req.new(plug: {Req.Test, @test_stub})
        {:ok, response} = Req.get(client, url: "https://api.example.com/users/123")

        assert response.status == 200
        assert response.body["name"] == "John Doe"
        assert response.body["profile"]["age"] == 30
        assert response.body["profile"]["interests"] == ["programming", "music", "travel"]
      end)
    end

    test "handles complex nested structures" do
      with_module_and_config(Jason, "Jason", :req_vcr, :json_library, ReqVCR.JSON.Jason, fn ->
        # Test deeply nested structure
        complex_data = %{
          "metadata" => %{
            "version" => "1.0",
            "timestamp" => 1_234_567_890,
            "environment" => %{
              "name" => "production",
              "region" => "us-east-1",
              "config" => %{
                "debug" => false,
                "features" => ["feature_a", "feature_b"],
                "limits" => %{
                  "max_users" => 1000,
                  "rate_limit" => 100
                }
              }
            }
          },
          "data" => [
            %{"id" => 1, "tags" => ["urgent", "bug"]},
            %{"id" => 2, "tags" => ["enhancement", "ui"]}
          ]
        }

        encoded = ReqVCR.JSON.encode!(complex_data)
        {:ok, decoded} = ReqVCR.JSON.decode(encoded)
        assert decoded == complex_data

        # Verify specific nested access
        assert decoded["metadata"]["environment"]["config"]["features"] == [
                 "feature_a",
                 "feature_b"
               ]

        assert decoded["data"] |> Enum.at(0) |> Map.get("tags") == ["urgent", "bug"]
      end)
    end

    test "preserves string encoding and special characters" do
      with_module_and_config(Jason, "Jason", :req_vcr, :json_library, ReqVCR.JSON.Jason, fn ->
        # Test Unicode and special characters
        special_data = %{
          "unicode" => "Hello 世界 🌍",
          "escaped" => "Line 1\nLine 2\tTabbed",
          "quotes" => ~s(He said "Hello" to me),
          "backslashes" => "Path\\to\\file",
          "mixed" => "Émojis: 🚀 ✨ 🎉 Chinese: 你好 Arabic: مرحبا"
        }

        encoded = ReqVCR.JSON.encode!(special_data)
        {:ok, decoded} = ReqVCR.JSON.decode(encoded)
        assert decoded == special_data

        # Verify specific characters are preserved
        assert decoded["unicode"] == "Hello 世界 🌍"
        assert decoded["escaped"] == "Line 1\nLine 2\tTabbed"
        assert decoded["quotes"] == ~s(He said "Hello" to me)
      end)
    end
  end
end
