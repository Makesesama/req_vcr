defmodule Reqord.CassetteState do
  @moduledoc """
  Manages cassette entry state across multiple processes using GenServer.

  This module solves the issue where concurrent requests (e.g., from Task.async)
  weren't being recorded because Reqord was using process-local storage.

  Following ExVCR's pattern, this uses GenServer for robust state management
  that can be accessed from any process.
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
      GenServer.stop(name)
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

  # GenServer Callbacks

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:append, entry}, state) do
    {:noreply, state ++ [entry]}
  end

  @impl true
  def handle_cast(:clear, _state) do
    {:noreply, []}
  end

  # Private functions

  defp state_name(cassette_path) do
    # Create a unique atom name for each cassette path
    # Use the cassette path hash to avoid atom leaks and handle long paths
    hash = :crypto.hash(:md5, cassette_path) |> Base.encode16(case: :lower)
    String.to_atom("reqord_cassette_#{hash}")
  end
end
