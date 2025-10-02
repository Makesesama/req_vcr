defmodule ReqVCR.JSON.Jason do
  @moduledoc """
  JSON adapter for the Jason library.

  This is the default JSON adapter used by ReqVCR. It provides encoding and
  decoding functionality using the Jason library.

  ## Features

  - Fast JSON encoding and decoding
  - Comprehensive error handling
  - Direct passthrough to Jason with consistent error format

  ## Usage

  This adapter is used by default. To explicitly configure it:

      config :req_vcr, :json_library, ReqVCR.JSON.Jason
  """

  @behaviour ReqVCR.JSON

  @impl ReqVCR.JSON
  def encode!(data) do
    ensure_jason_available!()
    Jason.encode!(data)
  end

  @impl ReqVCR.JSON
  def decode(binary) do
    ensure_jason_available!()
    Jason.decode(binary)
  end

  @impl ReqVCR.JSON
  def decode!(binary) do
    ensure_jason_available!()
    Jason.decode!(binary)
  end

  # Private functions

  defp ensure_jason_available! do
    unless Code.ensure_loaded?(Jason) do
      raise """
      Jason is not available.

      To use the default JSON adapter, add Jason to your dependencies in mix.exs:

          def deps do
            [
              {:jason, "~> 1.4"}
            ]
          end

      Alternatively, configure a different JSON adapter:

          config :req_vcr, :json_library, MyApp.JSONAdapter
      """
    end
  end
end
