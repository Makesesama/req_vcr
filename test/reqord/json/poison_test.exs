defmodule Reqord.JSON.PoisonTest do
  use ExUnit.Case
  import Reqord.TestHelpers

  @test_stub Reqord.JSON.PoisonTest.Stub
  @cassette_dir "test/support/cassettes"

  setup do
    # Ensure cassette directory exists
    File.mkdir_p!(@cassette_dir)

    # Set up Req.Test
    Req.Test.set_req_test_to_private()
    Req.Test.set_req_test_from_context(%{async: true})

    # Clean up test cassettes after each test
    _test_files = [
      "poison_adapter_basic.jsonl",
      "poison_adapter_complex.jsonl",
      "poison_adapter_integration.jsonl"
    ]

    on_exit(fn ->
      nil
      # Don't delete test files - they should persist
    end)

    :ok
  end

  describe "Poison adapter" do
    test "encodes and decodes basic data structures" do
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
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
          encoded = Reqord.JSON.encode!(data)
          assert is_binary(encoded)

          {:ok, decoded} = Reqord.JSON.decode(encoded)
          assert decoded == data

          decoded! = Reqord.JSON.decode!(encoded)
          assert decoded! == data
        end)
      end)
    end

    test "handles encoding/decoding errors properly" do
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
        # Test invalid JSON decoding
        {:error, error} = Reqord.JSON.decode("invalid json {")
        assert is_struct(error, Poison.ParseError)
        assert Exception.message(error) =~ "unexpected"

        # Test decode! with invalid JSON
        assert_raise Poison.ParseError, fn ->
          Reqord.JSON.decode!("invalid json {")
        end

        # Test encoding edge cases
        valid_data = %{"message" => "valid"}
        encoded = Reqord.JSON.encode!(valid_data)
        {:ok, decoded} = Reqord.JSON.decode(encoded)
        assert decoded == valid_data
      end)
    end

    test "creates and loads real cassettes" do
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
        # Create a realistic cassette entry
        cassette_path = Path.join(@cassette_dir, "poison_adapter_integration.jsonl")

        api_response_data = %{
          "id" => 456,
          "name" => "Jane Smith",
          "email" => "jane@example.com",
          "profile" => %{
            "age" => 28,
            "interests" => ["design", "photography", "hiking"]
          },
          "created_at" => "2024-01-15T09:30:00Z"
        }

        test_entry = %{
          req: %{
            method: "GET",
            url: "https://api.example.com/users/456",
            headers: %{"accept" => "application/json", "authorization" => "<REDACTED>"},
            body_hash: "-"
          },
          resp: %{
            status: 200,
            headers: %{"content-type" => "application/json", "x-request-id" => "req-456"},
            body_b64: Base.encode64(Poison.encode!(api_response_data))
          }
        }

        # Write cassette using Reqord.JSON
        encoded = Reqord.JSON.encode!(test_entry)
        File.write!(cassette_path, encoded <> "\n")

        # Verify file was written correctly
        content = File.read!(cassette_path)
        assert String.contains?(content, "https://api.example.com/users/456")
        assert String.contains?(content, "body_b64")

        # Verify we can load it back
        {:ok, decoded} = Reqord.JSON.decode(String.trim(content))
        assert decoded["req"]["method"] == "GET"
        assert decoded["resp"]["status"] == 200

        # Test VCR integration
        Reqord.install!(
          name: @test_stub,
          cassette: "poison_adapter_integration",
          mode: :once
        )

        client = Req.new(plug: {Req.Test, @test_stub})
        {:ok, response} = Req.get(client, url: "https://api.example.com/users/456")

        assert response.status == 200
        assert response.body["name"] == "Jane Smith"
        assert response.body["profile"]["age"] == 28
        assert response.body["profile"]["interests"] == ["design", "photography", "hiking"]
      end)
    end

    test "handles complex nested structures" do
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
        # Test deeply nested structure
        complex_data = %{
          "metadata" => %{
            "version" => "2.0",
            "timestamp" => 1_234_567_890,
            "environment" => %{
              "name" => "staging",
              "region" => "eu-west-1",
              "config" => %{
                "debug" => true,
                "features" => ["feature_c", "feature_d"],
                "limits" => %{
                  "max_users" => 500,
                  "rate_limit" => 50
                }
              }
            }
          },
          "data" => [
            %{"id" => 3, "tags" => ["critical", "security"]},
            %{"id" => 4, "tags" => ["feature", "backend"]}
          ]
        }

        encoded = Reqord.JSON.encode!(complex_data)
        {:ok, decoded} = Reqord.JSON.decode(encoded)
        assert decoded == complex_data

        # Verify specific nested access
        assert decoded["metadata"]["environment"]["config"]["features"] == [
                 "feature_c",
                 "feature_d"
               ]

        assert decoded["data"] |> Enum.at(0) |> Map.get("tags") == ["critical", "security"]
      end)
    end

    test "preserves string encoding and special characters" do
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
        # Test Unicode and special characters
        special_data = %{
          "unicode" => "Bonjour 世界 🌟",
          "escaped" => "Line 1\nLine 2\tTabbed",
          "quotes" => ~s(She said "Bonjour" to me),
          "backslashes" => "Path\\to\\file",
          "mixed" => "Símbolos: 🔥 ⭐ 🎈 Chinese: 再见 Russian: Привет"
        }

        encoded = Reqord.JSON.encode!(special_data)
        {:ok, decoded} = Reqord.JSON.decode(encoded)
        assert decoded == special_data

        # Verify specific characters are preserved
        assert decoded["unicode"] == "Bonjour 世界 🌟"
        assert decoded["escaped"] == "Line 1\nLine 2\tTabbed"
        assert decoded["quotes"] == ~s(She said "Bonjour" to me)
      end)
    end

    test "adapter module exists and has required functions" do
      # Test the adapter module exists
      adapter = Reqord.JSON.Poison

      assert is_atom(adapter)

      # Ensure the module is loaded before checking function exports
      Code.ensure_loaded!(adapter)
      assert function_exported?(adapter, :encode!, 1)
      assert function_exported?(adapter, :decode, 1)
      assert function_exported?(adapter, :decode!, 1)

      # If Poison is available, test basic functionality
      with_module_and_config(Poison, "Poison", :reqord, :json_library, Reqord.JSON.Poison, fn ->
        data = %{"test" => "poison works"}
        encoded = Reqord.JSON.encode!(data)
        {:ok, decoded} = Reqord.JSON.decode(encoded)
        assert decoded == data
      end)
    end
  end
end
