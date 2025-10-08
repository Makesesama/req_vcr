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

  Reqord supports multiple ways to organize your cassettes, with the following priority:

  ### 1. Explicit Path (`:vcr_path` tag)

  Use the `:vcr_path` tag to explicitly set the cassette path:

      @tag vcr_path: "providers/google/gemini-2.0-flash/basic_chat"
      test "basic chat" do
        # Uses "providers/google/gemini-2.0-flash/basic_chat.jsonl"
      end

  ### 2. Custom Path Builder Function

  Configure a global path builder function in your config:

      config :reqord,
        cassette_path_builder: fn context ->
          provider = context.tags[:provider] || "default"
          model = context.tags[:model] || "default"
          "\#{provider}/\#{model}/\#{context.test}"
        end

  Then use tags in your tests:

      @tag provider: "google", model: "gemini-2.0-flash"
      test "basic chat" do
        # Uses "google/gemini-2.0-flash/test_basic_chat.jsonl"
      end

  ### 3. Simple Name Override (`:vcr` tag)

  Override with a simple name using the `:vcr` tag:

      @tag vcr: "my_custom_cassette"
      test "example" do
        # Uses "my_custom_cassette.jsonl"
      end

  ### 4. Default Behavior

  By default, cassettes are named after the test module and test name:
  `"ModuleName/test_name.jsonl"`

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
        stub_name = context[:req_stub_name] || default_stub_name()
        mode = vcr_mode(context)
        cassette_name = cassette_name(context)
        match_on = context[:match_on] || Application.get_env(:reqord, :match_on, [:method, :uri])

        Req.Test.set_req_test_to_private()
        Req.Test.set_req_test_from_context(context)

        Reqord.install!(
          name: stub_name,
          cassette: cassette_name,
          mode: mode,
          match_on: match_on
        )

        ExUnit.Callbacks.on_exit(fn ->
          Reqord.cleanup(cassette_name, mode)
        end)

        Req.Test.verify_on_exit!(context)

        :ok
      end

      defp default_stub_name do
        module_name = __MODULE__ |> Module.split() |> List.first()
        Module.concat([module_name, "ReqStub"])
      end

      defp vcr_mode(context) do
        cond do
          context[:vcr_mode] || context[:integration_mode] ->
            context[:vcr_mode] || context[:integration_mode]

          env_mode = System.get_env("REQORD") ->
            parse_mode(env_mode)

          app_mode = Application.get_env(:reqord, :default_mode) ->
            app_mode

          true ->
            :none
        end
      end

      defp parse_mode(mode_str) do
        case String.downcase(mode_str) do
          "once" -> :once
          "new_episodes" -> :new_episodes
          "all" -> :all
          "none" -> :none
          _ -> :none
        end
      end

      defp cassette_name(context) do
        cond do
          # 1. Explicit path via :vcr_path tag (highest priority)
          path = context[:vcr_path] ->
            path

          # 2. Custom path builder function from config
          builder = Application.get_env(:reqord, :cassette_path_builder) ->
            builder.(context)

          # 3. Simple name override via :vcr tag (backwards compatibility)
          true ->
            case context[:vcr] || context[:integration] do
              name when is_binary(name) ->
                name

              _ ->
                # 4. Default behavior - auto-generate from module and test name
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
      end

      defoverridable default_stub_name: 0
    end
  end
end
