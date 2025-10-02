defmodule Reqord.Config do
  @moduledoc """
  Configuration management for Reqord.

  This module provides centralized access to all configurable settings,
  with sensible defaults and the ability to override via application config.

  ## Configuration Options

  ### Cassette Directory

      config :reqord, :cassette_dir, "test/support/cassettes"

  ### Auth Parameters (for redaction)

      config :reqord, :auth_params, ~w[token apikey api_key access_token refresh_token jwt bearer password secret]

  ### Auth Headers (for redaction)

      config :reqord, :auth_headers, ~w[authorization auth x-api-key x-auth-token x-access-token cookie]

  ### Volatile Headers (removed from responses)

      config :reqord, :volatile_headers, ~w[date server set-cookie request-id x-request-id x-amzn-trace-id]

  ### JSON Library

      config :reqord, :json_library, Reqord.JSON.Jason

  ### Default Record Mode

      config :reqord, :default_mode, :once

  ### Custom Filters (for additional redaction)

      config :reqord, :filters, [
        {"<API_KEY>", fn -> System.get_env("API_KEY") end},
        {"<SHOPIFY_TOKEN>", fn -> Application.get_env(:my_app, :shopify_token) end}
      ]
  """

  @default_cassette_dir "test/support/cassettes"
  @default_auth_params ~w[token apikey api_key access_token refresh_token jwt bearer password secret]
  @default_auth_headers ~w[authorization auth x-api-key x-auth-token x-access-token cookie]
  @default_volatile_headers ~w[date server set-cookie request-id x-request-id x-amzn-trace-id]

  @doc """
  Gets the configured cassette directory.

  Defaults to "test/support/cassettes" if not configured.

  ## Examples

      iex> Reqord.Config.cassette_dir()
      "test/support/cassettes"

      # With custom config
      iex> Application.put_env(:reqord, :cassette_dir, "test/cassettes")
      iex> Reqord.Config.cassette_dir()
      "test/cassettes"
  """
  @spec cassette_dir() :: String.t()
  def cassette_dir do
    Application.get_env(:reqord, :cassette_dir, @default_cassette_dir)
  end

  @doc """
  Gets the list of auth parameter names that should be redacted.

  These parameters will be replaced with "<REDACTED>" in cassette files.

  ## Examples

      iex> Reqord.Config.auth_params()
      ["token", "apikey", "api_key", "access_token", "refresh_token", "jwt", "bearer", "password", "secret"]
  """
  @spec auth_params() :: [String.t()]
  def auth_params do
    Application.get_env(:reqord, :auth_params, @default_auth_params)
  end

  @doc """
  Gets the list of auth header names that should be redacted.

  These headers will be replaced with "<REDACTED>" in cassette files.

  ## Examples

      iex> Reqord.Config.auth_headers()
      ["authorization", "auth", "x-api-key", "x-auth-token", "x-access-token", "cookie"]
  """
  @spec auth_headers() :: [String.t()]
  def auth_headers do
    Application.get_env(:reqord, :auth_headers, @default_auth_headers)
  end

  @doc """
  Gets the list of volatile headers that should be removed from responses.

  These headers change between requests and would make cassettes unreliable.

  ## Examples

      iex> Reqord.Config.volatile_headers()
      ["date", "server", "set-cookie", "request-id", "x-request-id", "x-amzn-trace-id"]
  """
  @spec volatile_headers() :: [String.t()]
  def volatile_headers do
    Application.get_env(:reqord, :volatile_headers, @default_volatile_headers)
  end

  @doc """
  Gets the configured JSON library module.

  Defaults to Reqord.JSON.Jason if not configured.

  ## Examples

      iex> Reqord.Config.json_library()
      Reqord.JSON.Jason
  """
  @spec json_library() :: module()
  def json_library do
    Application.get_env(:reqord, :json_library, Reqord.JSON.Jason)
  end

  @doc """
  Gets the default record mode.

  Defaults to :once if not configured.

  ## Examples

      iex> Reqord.Config.default_mode()
      :once
  """
  @spec default_mode() :: :once | :new_episodes | :all | :none
  def default_mode do
    Application.get_env(:reqord, :default_mode, :once)
  end

  @doc """
  Gets custom filters for additional redaction.

  Returns a list of {replacement, value_function} tuples.

  ## Examples

      iex> Reqord.Config.custom_filters()
      []

      # With custom filters configured
      iex> Application.put_env(:reqord, :filters, [{"<API_KEY>", fn -> "secret123" end}])
      iex> Reqord.Config.custom_filters()
      [{"<API_KEY>", #Function<...>}]
  """
  @spec custom_filters() :: [{String.t(), (-> String.t() | nil)}]
  def custom_filters do
    Application.get_env(:reqord, :filters, [])
  end

  @doc """
  Gets the directory path for a given cassette name.

  Combines the cassette directory with the cassette name and ensures
  the directory exists.

  ## Examples

      iex> Reqord.Config.cassette_path("my_test")
      "test/support/cassettes/my_test.jsonl"
  """
  @spec cassette_path(String.t()) :: String.t()
  def cassette_path(cassette_name) do
    dir = cassette_dir()
    File.mkdir_p!(dir)
    Path.join(dir, "#{cassette_name}.jsonl")
  end

  @doc """
  Validates the current configuration and returns any errors.

  Useful for debugging configuration issues.

  ## Examples

      iex> Reqord.Config.validate()
      :ok

      iex> Application.put_env(:reqord, :cassette_dir, "/nonexistent/readonly")
      iex> Reqord.Config.validate()
      {:error, [{:cassette_dir, "Directory /nonexistent/readonly is not writable"}]}
  """
  @spec validate() :: :ok | {:error, [{atom(), String.t()}]}
  def validate do
    errors = []

    errors =
      case validate_cassette_dir() do
        :ok -> errors
        {:error, message} -> [{:cassette_dir, message} | errors]
      end

    errors =
      case validate_json_library() do
        :ok -> errors
        {:error, message} -> [{:json_library, message} | errors]
      end

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Private helper functions

  defp validate_cassette_dir do
    dir = cassette_dir()

    cond do
      not is_binary(dir) ->
        {:error, "Cassette directory must be a string, got: #{inspect(dir)}"}

      String.trim(dir) == "" ->
        {:error, "Cassette directory cannot be empty"}

      true ->
        # Try to create the directory to test writability
        case File.mkdir_p(dir) do
          :ok -> :ok
          {:error, reason} -> {:error, "Cannot create cassette directory: #{reason}"}
        end
    end
  end

  defp validate_json_library do
    library = json_library()

    cond do
      not is_atom(library) ->
        {:error, "JSON library must be a module atom, got: #{inspect(library)}"}

      not Code.ensure_loaded?(library) ->
        {:error, "JSON library module #{inspect(library)} could not be loaded"}

      not function_exported?(library, :encode!, 1) ->
        {:error, "JSON library #{inspect(library)} must export encode!/1"}

      not function_exported?(library, :decode, 1) ->
        {:error, "JSON library #{inspect(library)} must export decode/1"}

      not function_exported?(library, :decode!, 1) ->
        {:error, "JSON library #{inspect(library)} must export decode!/1"}

      true ->
        :ok
    end
  end
end
