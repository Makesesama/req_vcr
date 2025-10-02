defmodule ReqVCR.JSON do
  @moduledoc """
  Behavior for JSON encoding and decoding.

  This allows users to configure their preferred JSON library for use with ReqVCR.
  By default, ReqVCR uses Jason, but you can configure it to use any JSON library
  that implements this behavior.

  ## Configuration

  In your application config:

      config :req_vcr, :json_library, MyApp.JSONAdapter

  ## Built-in Adapters

  - `ReqVCR.JSON.Jason` - Default adapter using the Jason library

  ## Custom Adapters

  To create a custom adapter, implement this behavior:

      defmodule MyApp.JSONAdapter do
        @behaviour ReqVCR.JSON

        @impl ReqVCR.JSON
        def encode!(data) do
          MyJSONLibrary.encode!(data)
        end

        @impl ReqVCR.JSON
        def decode(binary) do
          case MyJSONLibrary.decode(binary) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, %MyJSONLibrary.Error{reason: reason}}
          end
        end

        @impl ReqVCR.JSON
        def decode!(binary) do
          MyJSONLibrary.decode!(binary)
        end
      end
  """

  @type json_data :: term()
  @type json_binary :: binary()
  @type decode_error :: Exception.t()

  @doc """
  Encodes Elixir data to JSON binary.

  Raises an exception if encoding fails.
  """
  @callback encode!(json_data()) :: json_binary()

  @doc """
  Decodes JSON binary to Elixir data.

  Returns `{:ok, data}` on success or `{:error, exception}` on failure.
  """
  @callback decode(json_binary()) :: {:ok, json_data()} | {:error, decode_error()}

  @doc """
  Decodes JSON binary to Elixir data.

  Raises an exception if decoding fails.
  """
  @callback decode!(json_binary()) :: json_data()

  @doc """
  Encodes Elixir data to JSON binary using the configured adapter.

  ## Examples

      iex> ReqVCR.JSON.encode!(%{name: "John"})
      ~s({"name":"John"})
  """
  @spec encode!(json_data()) :: json_binary()
  def encode!(data) do
    adapter().encode!(data)
  end

  @doc """
  Decodes JSON binary to Elixir data using the configured adapter.

  ## Examples

      iex> ReqVCR.JSON.decode(~s({"name":"John"}))
      {:ok, %{"name" => "John"}}

      iex> ReqVCR.JSON.decode("invalid json")
      {:error, %Jason.DecodeError{...}}
  """
  @spec decode(json_binary()) :: {:ok, json_data()} | {:error, decode_error()}
  def decode(binary) do
    adapter().decode(binary)
  end

  @doc """
  Decodes JSON binary to Elixir data using the configured adapter.

  Raises an exception if decoding fails.

  ## Examples

      iex> ReqVCR.JSON.decode!(~s({"name":"John"}))
      %{"name" => "John"}
  """
  @spec decode!(json_binary()) :: json_data()
  def decode!(binary) do
    adapter().decode!(binary)
  end

  # Private functions

  defp adapter do
    Application.get_env(:req_vcr, :json_library, ReqVCR.JSON.Jason)
  end
end
