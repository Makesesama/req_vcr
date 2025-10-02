defmodule ReqVCR.Redactor do
  @moduledoc """
  Handles redaction of sensitive data from HTTP requests and responses.

  This module provides VCR-style filtering to ensure that secrets, API keys,
  tokens, and other sensitive information are never stored in cassette files.

  ## Configuration

  Configure sensitive data filters in your application config:

      config :req_vcr, :filters, [
        {"<API_KEY>", fn -> System.get_env("API_KEY") end},
        {"<TOKEN>", fn -> Application.get_env(:my_app, :api_token) end}
      ]

  ## Built-in Redaction

  Even without explicit configuration, common auth patterns are automatically redacted:
  - Authorization headers
  - Common auth query parameters (token, api_key, etc.)
  - Bearer tokens in response bodies
  - Long alphanumeric strings that look like secrets
  """

  @default_auth_params ~w[token apikey api_key access_token refresh_token jwt bearer password secret]
  @default_auth_headers ~w[authorization auth x-api-key x-auth-token x-access-token cookie]

  @doc """
  Redacts sensitive information from request headers.

  ## Examples

      iex> ReqVCR.Redactor.redact_headers([{"authorization", "Bearer secret123"}])
      %{"authorization" => "<REDACTED>"}

      iex> ReqVCR.Redactor.redact_headers([{"content-type", "application/json"}])
      %{"content-type" => "application/json"}
  """
  @spec redact_headers(list() | map()) :: map()
  def redact_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(&redact_header_value/1)
    |> apply_configured_filters()
    |> Enum.into(%{})
  end

  def redact_headers(headers) when is_map(headers) do
    headers
    |> Enum.to_list()
    |> redact_headers()
  end

  @doc """
  Redacts sensitive information from URLs by removing auth query parameters.

  ## Examples

      iex> ReqVCR.Redactor.redact_url("https://api.com/users?token=secret&name=john")
      "https://api.com/users?name=john&token=<REDACTED>"
  """
  @spec redact_url(String.t()) :: String.t()
  def redact_url(url) do
    uri = URI.parse(url)

    redacted_query =
      if uri.query do
        uri.query
        |> URI.decode_query()
        |> Enum.map(fn {key, value} ->
          if String.downcase(key) in @default_auth_params do
            {key, "<REDACTED>"}
          else
            # Apply configured filters to query parameter values
            {key, apply_configured_filters_to_value(value)}
          end
        end)
        |> URI.encode_query()
      else
        nil
      end

    %{uri | query: redacted_query}
    |> URI.to_string()
  end

  @doc """
  Redacts sensitive information from response bodies.

  This handles JSON responses, Bearer tokens, API keys, and other patterns
  that might contain secrets.

  ## Examples

      iex> ReqVCR.Redactor.redact_response_body(~s({"access_token": "secret123"}))
      ~s({"access_token": "<REDACTED>"})
  """
  @spec redact_response_body(binary()) :: binary()
  def redact_response_body(body) when is_binary(body) do
    body
    |> apply_configured_filters_to_value()
    |> redact_json_secrets()
    |> redact_bearer_tokens()
    |> redact_api_keys()
  end

  def redact_response_body(body), do: body

  # Private functions

  # Redact secrets in JSON responses
  defp redact_json_secrets(body) do
    case ReqVCR.JSON.decode(body) do
      {:ok, json} ->
        json
        |> redact_json_values()
        |> ReqVCR.JSON.encode!()

      {:error, _} ->
        # Not valid JSON, return as-is
        body
    end
  rescue
    exception ->
      # Log unexpected errors but don't crash redaction
      require Logger
      Logger.warning("Unexpected error during JSON redaction: #{inspect(exception)}")
      body
  end

  defp redact_json_values(json) when is_map(json) do
    json
    |> Enum.map(fn {key, value} ->
      key_lower = String.downcase(to_string(key))

      if key_lower in @default_auth_params or
           String.contains?(key_lower, ["token", "key", "secret", "password"]) do
        {key, "<REDACTED>"}
      else
        {key, redact_json_values(value)}
      end
    end)
    |> Enum.into(%{})
  end

  defp redact_json_values(json) when is_list(json) do
    Enum.map(json, &redact_json_values/1)
  end

  defp redact_json_values(value), do: value

  # Redact Bearer tokens in response bodies
  defp redact_bearer_tokens(body) do
    Regex.replace(~r/Bearer\s+[a-zA-Z0-9_-]+/i, body, "Bearer <REDACTED>")
  end

  # Redact API keys and long alphanumeric strings that look like secrets
  defp redact_api_keys(body) do
    body
    |> String.replace(~r/ghp_[a-zA-Z0-9]{40}/, "<REDACTED>")
    |> String.replace(~r/sk_[a-zA-Z0-9]+/, "<REDACTED>")
    |> String.replace(~r/pk_[a-zA-Z0-9]+/, "<REDACTED>")
    |> String.replace(
      ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i,
      "<REDACTED>"
    )
    |> String.replace(~r/[a-zA-Z0-9]{32,}/, "<REDACTED>")
  end

  # Redact individual header values based on built-in patterns
  defp redact_header_value({key, value}) do
    if String.downcase(key) in @default_auth_headers do
      {key, "<REDACTED>"}
    else
      {key, value}
    end
  end

  # Apply configured filters to headers
  defp apply_configured_filters(headers) do
    configured_filters()
    |> Enum.reduce(headers, fn {placeholder, filter_fn}, acc ->
      filter_value = filter_fn.()

      Enum.map(acc, fn {key, value} ->
        {key, String.replace(value, filter_value, placeholder)}
      end)
    end)
  end

  # Get configured filters from application config
  defp configured_filters do
    Application.get_env(:req_vcr, :filters, [])
  end

  # Apply configured filters to a single value
  defp apply_configured_filters_to_value(value) do
    configured_filters()
    |> Enum.reduce(value, fn {placeholder, filter_fn}, acc ->
      filter_value = filter_fn.()
      String.replace(acc, filter_value, placeholder)
    end)
  end
end
