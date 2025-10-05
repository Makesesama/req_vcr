defmodule Reqord.Case do
  @moduledoc """
  ExUnit case template for using Reqord in tests.

  This module provides automatic cassette management and Req.Test integration
  for your tests.

  ## Usage

      defmodule MyAppTest do
        use Reqord.Case

        test "makes API call" do
          # Requests will automatically use cassettes
          {:ok, resp} = Req.get("https://api.example.com/data")
          assert resp.status == 200
        end

        @tag vcr: "custom/cassette/name"
        test "with custom cassette name" do
          # Will use custom cassette name instead of auto-generated
        end

        @tag req_stub_name: MyApp.CustomStub
        test "with custom stub name" do
          # Will use custom Req.Test stub name
        end
      end

  ## Configuration

  Set the VCR record mode via the `REQORD` environment variable or application config.

  ### Environment Variable

  - `REQORD=once` - Strict replay, raise on new requests
  - `REQORD=new_episodes` - Replay existing, record new requests
  - `REQORD=all` - Always hit live network and re-record
  - `REQORD=none` - Never record, never hit network (default)

  ### Application Config

  You can also configure the default mode in your config files:

      config :reqord, default_mode: :none

  ### Per-Test Mode

  Override mode for specific tests using tags:

      @tag vcr_mode: :new_episodes
      test "allows new recordings" do
        # This test will record new requests
      end

  ### Per-Test Matchers

  Override matchers for specific tests:

      @tag match_on: [:method, :path, :body]
      test "matches on method, path, and body" do
        # This test uses custom matchers
      end

  ## Cassette Naming

  By default, cassettes are named after the test module and test name:
  `"ModuleName/test_name.jsonl"`

  Override with the `:vcr` tag:

      @tag vcr: "my_custom_cassette"
      test "example" do
        # Uses "my_custom_cassette.jsonl"
      end

  ## Spawned Processes

  If your test spawns processes that make HTTP requests, you need to allow them:

      test "with spawned process" do
        task = Task.async(fn ->
          Req.get("https://api.example.com/data")
        end)

        Reqord.allow(MyApp.ReqStub, self(), task.pid)
        Task.await(task)
      end
  """

  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, unquote(opts)

      setup context do
        # Get configuration from context tags or defaults
        stub_name = context[:req_stub_name] || default_stub_name()
        mode = vcr_mode(context)
        cassette_name = cassette_name(context)
        match_on = context[:match_on] || Application.get_env(:reqord, :match_on, [:method, :uri])

        # Set up Req.Test in private mode
        Req.Test.set_req_test_to_private()
        Req.Test.set_req_test_from_context(context)

        # Install VCR
        Reqord.install!(
          name: stub_name,
          cassette: cassette_name,
          mode: mode,
          match_on: match_on
        )

        # Ensure cassette is flushed on test exit
        ExUnit.Callbacks.on_exit(fn ->
          Reqord.cleanup(cassette_name, mode)
        end)

        # Verify on exit
        Req.Test.verify_on_exit!(context)

        :ok
      end

      # Helper to get the default stub name
      # Override this in your test module if needed
      defp default_stub_name do
        # Extract the base module name and use it as the stub name
        # e.g., MyApp.FeatureTest -> MyApp.ReqStub
        module_name = __MODULE__ |> Module.split() |> List.first()
        Module.concat([module_name, "ReqStub"])
      end

      # Get VCR mode from context tag, env var, or app config
      defp vcr_mode(context) do
        cond do
          # 1. Check for per-test tag override (check both :vcr_mode and :integration_mode)
          context[:vcr_mode] || context[:integration_mode] ->
            context[:vcr_mode] || context[:integration_mode]

          # 2. Check environment variable
          env_mode = System.get_env("REQORD") ->
            parse_mode(env_mode)

          # 3. Check application config
          app_mode = Application.get_env(:reqord, :default_mode) ->
            app_mode

          # 4. Default to :none
          true ->
            :none
        end
      end

      # Parse mode string from environment variable
      defp parse_mode(mode_str) do
        case String.downcase(mode_str) do
          "once" -> :once
          "new_episodes" -> :new_episodes
          "all" -> :all
          "none" -> :none
          _ -> :none
        end
      end

      # Generate cassette name from context
      defp cassette_name(context) do
        # Allow override via tag (check both :vcr and :integration for backwards compatibility)
        case context[:vcr] || context[:integration] do
          name when is_binary(name) ->
            name

          _ ->
            # Auto-generate from module and test name
            module_name =
              __MODULE__
              |> Module.split()
              |> List.last()
              |> String.replace(~r/Test$/, "")

            test_name =
              context.test
              |> Atom.to_string()
              |> String.replace(~r/^test /, "")
              |> String.replace(~r/\s+/, "_")

            "#{module_name}/#{test_name}"
        end
      end

      defoverridable default_stub_name: 0
    end
  end
end
