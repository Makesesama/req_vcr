defmodule Reqord.JSONAdapterTest do
  use ExUnit.Case

  describe "JSON behavior" do
    test "uses default Jason adapter" do
      data = %{"name" => "John", "age" => 30}

      # Test encoding
      encoded = Reqord.JSON.encode!(data)
      assert is_binary(encoded)
      assert String.contains?(encoded, "John")

      # Test decoding
      {:ok, decoded} = Reqord.JSON.decode(encoded)
      assert decoded == data

      # Test decode!
      decoded! = Reqord.JSON.decode!(encoded)
      assert decoded! == data
    end

    test "handles invalid JSON gracefully" do
      # Test decode with invalid JSON
      {:error, error} = Reqord.JSON.decode("invalid json")
      assert Exception.message(error) =~ "unexpected byte"

      # Test decode! with invalid JSON
      assert_raise Jason.DecodeError, fn ->
        Reqord.JSON.decode!("invalid json")
      end
    end
  end

  describe "custom JSON adapter" do
    defmodule MockJSONAdapter do
      @behaviour Reqord.JSON

      @impl Reqord.JSON
      def encode!(data) do
        "MOCK:" <> Jason.encode!(data)
      end

      @impl Reqord.JSON
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

      @impl Reqord.JSON
      def decode!(binary) do
        case decode(binary) do
          {:ok, data} -> data
          {:error, error} -> raise error
        end
      end
    end

    test "can use custom adapter when configured" do
      # Save original config
      original_adapter = Application.get_env(:reqord, :json_library)

      try do
        # Configure custom adapter
        Application.put_env(:reqord, :json_library, MockJSONAdapter)

        data = %{"test" => "value"}

        # Test encoding with custom adapter
        encoded = Reqord.JSON.encode!(data)
        assert String.starts_with?(encoded, "MOCK:")
        assert String.contains?(encoded, "test")

        # Test decoding with custom adapter
        {:ok, decoded} = Reqord.JSON.decode(encoded)
        assert decoded == data

        # Test decode! with custom adapter
        decoded! = Reqord.JSON.decode!(encoded)
        assert decoded! == data

        # Test error handling with custom adapter
        {:error, error} = Reqord.JSON.decode("regular json")
        assert Exception.message(error) == "Not a mock JSON format"
      after
        # Restore original config
        if original_adapter do
          Application.put_env(:reqord, :json_library, original_adapter)
        else
          Application.delete_env(:reqord, :json_library)
        end
      end
    end
  end
end
