defmodule Reqord.JSON.Poison do
  @moduledoc """
  JSON adapter for the Poison library.

  This adapter allows using Poison instead of Jason for JSON encoding/decoding.

  ## Usage

  Add Poison to your dependencies and configure Reqord to use it:

      # mix.exs
      def deps do
        [
          {:poison, "~> 5.0"},
          {:reqord, "~> 0.1.0"}
        ]
      end

      # config/config.exs
      config :reqord, :json_library, Reqord.JSON.Poison

  ## Features

  - Pure Elixir implementation
  - Good performance for most use cases
  - Wide ecosystem compatibility
  """

  @behaviour Reqord.JSON

  @impl Reqord.JSON
  def encode!(data) do
    ensure_poison_available!()
    Poison.encode!(data)
  end

  @impl Reqord.JSON
  def decode(binary) do
    ensure_poison_available!()
    Poison.decode(binary)
  end

  @impl Reqord.JSON
  def decode!(binary) do
    ensure_poison_available!()
    Poison.decode!(binary)
  end

  # Private functions

  defp ensure_poison_available! do
    unless Code.ensure_loaded?(Poison) do
      raise """
      Poison is not available.

      To use the Poison JSON adapter, add Poison to your dependencies in mix.exs:

          def deps do
            [
              {:poison, "~> 5.0"}
            ]
          end

      Then configure Reqord to use it:

          config :reqord, :json_library, Reqord.JSON.Poison
      """
    end
  end
end
