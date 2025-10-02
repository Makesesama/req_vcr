defmodule ReqVCR.JSONAdapterTest do
  use ExUnit.Case

  describe "JSON behavior" do
    test "uses default Jason adapter" do
      data = %{"name" => "John", "age" => 30}

      # Test encoding
      encoded = ReqVCR.JSON.encode!(data)
      assert is_binary(encoded)
      assert String.contains?(encoded, "John")

      # Test decoding
      {:ok, decoded} = ReqVCR.JSON.decode(encoded)
      assert decoded == data

      # Test decode!
      decoded! = ReqVCR.JSON.decode!(encoded)
      assert decoded! == data
    end

    test "handles invalid JSON gracefully" do
      # Test decode with invalid JSON
      {:error, error} = ReqVCR.JSON.decode("invalid json")
      assert Exception.message(error) =~ "unexpected byte"

      # Test decode! with invalid JSON
      assert_raise Jason.DecodeError, fn ->
        ReqVCR.JSON.decode!("invalid json")
      end
    end
  end

  describe "custom JSON adapter" do
    defmodule MockJSONAdapter do
      @behaviour ReqVCR.JSON

      @impl ReqVCR.JSON
      def encode!(data) do
        "MOCK:" <> Jason.encode!(data)
      end

      @impl ReqVCR.JSON
      def decode(binary) do
        case String.starts_with?(binary, "MOCK:") do
          true ->
            binary
            |> String.replace_prefix("MOCK:", "")
            |> Jason.decode()

          false ->
            {:error, %RuntimeError{message: "Not a mock JSON format"}}
        end
      end

      @impl ReqVCR.JSON
      def decode!(binary) do
        case decode(binary) do
          {:ok, data} -> data
          {:error, error} -> raise error
        end
      end
    end

    test "can use custom adapter when configured" do
      # Save original config
      original_adapter = Application.get_env(:req_vcr, :json_library)

      try do
        # Configure custom adapter
        Application.put_env(:req_vcr, :json_library, MockJSONAdapter)

        data = %{"test" => "value"}

        # Test encoding with custom adapter
        encoded = ReqVCR.JSON.encode!(data)
        assert String.starts_with?(encoded, "MOCK:")
        assert String.contains?(encoded, "test")

        # Test decoding with custom adapter
        {:ok, decoded} = ReqVCR.JSON.decode(encoded)
        assert decoded == data

        # Test decode! with custom adapter
        decoded! = ReqVCR.JSON.decode!(encoded)
        assert decoded! == data

        # Test error handling with custom adapter
        {:error, error} = ReqVCR.JSON.decode("regular json")
        assert Exception.message(error) == "Not a mock JSON format"
      after
        # Restore original config
        if original_adapter do
          Application.put_env(:req_vcr, :json_library, original_adapter)
        else
          Application.delete_env(:req_vcr, :json_library)
        end
      end
    end
  end
end
