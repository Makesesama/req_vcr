defmodule Reqord.CassetteState do
  @moduledoc """
  Manages cassette entry state across multiple processes using GenServer.

  This module solves the issue where concurrent requests (e.g., from Task.async)
  weren't being recorded because Reqord was using process-local storage.

  Following ExVCR's pattern, this uses GenServer for robust state management
  that can be accessed from any process.

  Additionally, this module manages per-process cassette context, which allows
  macro-generated tests to provide additional metadata for cassette naming.
  """

  use GenServer

  @doc """
  Starts a named GenServer for a specific cassette.
  """
  @spec start_for_cassette(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_for_cassette(cassette_path) do
    name = state_name(cassette_path)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc """
  Stops the named GenServer for a cassette.
  """
  @spec stop_for_cassette(String.t()) :: :ok
  def stop_for_cassette(cassette_path) do
    name = state_name(cassette_path)

    if Process.whereis(name) do
      try do
        GenServer.stop(name)
      catch
        :exit, {:noproc, _} -> :ok
      end
    end

    :ok
  end

  @doc """
  Gets the current accumulated entries for a cassette.
  Returns empty list if no state exists.
  """
  @spec get_entries(String.t()) :: [Reqord.CassetteEntry.t()]
  def get_entries(cassette_path) do
    name = state_name(cassette_path)

    case Process.whereis(name) do
      nil -> []
      _pid -> GenServer.call(name, :get)
    end
  end

  @doc """
  Gets the current replay position for a cassette.
  Returns 0 if no state exists.
  """
  @spec get_replay_position(String.t()) :: non_neg_integer()
  def get_replay_position(cassette_path) do
    name = state_name(cassette_path)

    case Process.whereis(name) do
      nil -> 0
      _pid -> GenServer.call(name, :get_position)
    end
  end

  @doc """
  Advances the replay position for a cassette.
  Creates the state if it doesn't exist.
  """
  @spec advance_replay_position(String.t()) :: :ok
  def advance_replay_position(cassette_path) do
    name = state_name(cassette_path)

    # Ensure GenServer exists
    unless Process.whereis(name) do
      start_for_cassette(cassette_path)
    end

    GenServer.cast(name, :advance_position)
  end

  @doc """
  Appends a new entry to the cassette state.
  Creates the state if it doesn't exist.
  """
  @spec append_entry(String.t(), Reqord.CassetteEntry.t()) :: :ok
  def append_entry(cassette_path, entry) do
    name = state_name(cassette_path)

    # Ensure GenServer exists
    unless Process.whereis(name) do
      start_for_cassette(cassette_path)
    end

    GenServer.cast(name, {:append, entry})
  end

  @doc """
  Clears all entries for a cassette.
  """
  @spec clear_entries(String.t()) :: :ok
  def clear_entries(cassette_path) do
    name = state_name(cassette_path)

    # Ensure GenServer exists
    unless Process.whereis(name) do
      start_for_cassette(cassette_path)
    end

    GenServer.cast(name, :clear)
  end

  @doc """
  Resets the replay position to 0 for a cassette.
  """
  @spec reset_replay_position(String.t()) :: :ok
  def reset_replay_position(cassette_path) do
    name = state_name(cassette_path)

    # Ensure GenServer exists
    unless Process.whereis(name) do
      start_for_cassette(cassette_path)
    end

    GenServer.cast(name, :reset_position)
  end

  @doc """
  Stores cassette context for the current process.

  This allows macro-generated tests to provide additional metadata that will be
  merged with the test context when determining cassette names.

  ## Examples

      # In a macro-generated test setup
      Reqord.CassetteState.put_context(self(), %{
        provider: "google",
        model: "gemini-2.0-flash"
      })

  """
  @spec put_context(pid(), map()) :: :ok
  def put_context(pid, context) when is_pid(pid) and is_map(context) do
    Process.put({:reqord_cassette_context, pid}, context)
    :ok
  end

  @doc """
  Retrieves cassette context for the current process.

  Returns an empty map if no context has been set.

  ## Examples

      iex> Reqord.CassetteState.get_context(self())
      %{}

      iex> Reqord.CassetteState.put_context(self(), %{model: "gpt-4"})
      iex> Reqord.CassetteState.get_context(self())
      %{model: "gpt-4"}

  """
  @spec get_context(pid()) :: map()
  def get_context(pid) when is_pid(pid) do
    Process.get({:reqord_cassette_context, pid}, %{})
  end

  @doc """
  Clears cassette context for the current process.
  """
  @spec clear_context(pid()) :: :ok
  def clear_context(pid) when is_pid(pid) do
    Process.delete({:reqord_cassette_context, pid})
    :ok
  end

  # GenServer Callbacks

  @impl true
  def init(_) do
    # State is now {entries, replay_position}
    {:ok, {[], 0}}
  end

  @impl true
  def handle_call(:get, _from, {entries, _position} = state) do
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:get_position, _from, {_entries, position} = state) do
    {:reply, position, state}
  end

  @impl true
  def handle_cast({:append, entry}, {entries, position}) do
    {:noreply, {entries ++ [entry], position}}
  end

  @impl true
  def handle_cast(:clear, {_entries, _position}) do
    # Reset both entries and position
    {:noreply, {[], 0}}
  end

  @impl true
  def handle_cast(:advance_position, {entries, position}) do
    {:noreply, {entries, position + 1}}
  end

  @impl true
  def handle_cast(:reset_position, {entries, _position}) do
    {:noreply, {entries, 0}}
  end

  # Private functions

  defp state_name(cassette_path) do
    # Create a unique atom name for each cassette path
    # Use the cassette path hash to avoid atom leaks and handle long paths
    hash = :crypto.hash(:md5, cassette_path) |> Base.encode16(case: :lower)
    String.to_atom("reqord_cassette_#{hash}")
  end
end
