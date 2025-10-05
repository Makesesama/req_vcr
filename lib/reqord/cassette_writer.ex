defmodule Reqord.CassetteWriter do
  @moduledoc """
  GenServer for asynchronously writing cassette entries with timestamp-based ordering.

  The CassetteWriter is a core component of Reqord's new architecture that
  solves concurrent request ordering issues. It provides:

  - **Async writes**: Non-blocking cassette writes during test execution
  - **Timestamp sorting**: Automatic chronological ordering of entries before writing
  - **Intelligent batching**: Configurable batch sizes and timeouts for optimal I/O
  - **Crash recovery**: Supervised GenServer with automatic restart
  - **Backpressure handling**: Graceful handling of high-volume recording scenarios

  ## How It Works

  When a request is recorded, the writer:
  1. Adds the entry to a pending batch for that cassette
  2. Starts/resets a batch timer
  3. When batch size is reached OR timer expires:
     - Sorts all pending entries by `recorded_at` timestamp
     - Writes the sorted batch to the storage backend
     - Clears pending entries for that cassette

  This ensures that even if concurrent requests complete out of order, they are
  written to cassettes in chronological order based on when they were initiated.

  ## Configuration

  The writer can be configured via application config:

      config :reqord,
        writer_config: %{
          batch_size: 10,        # Max entries per batch
          batch_timeout: 100,    # Max wait time in milliseconds
        }

  ## Supervision

  The CassetteWriter is automatically started by the Reqord.Application supervisor
  and will be restarted if it crashes. All pending writes are flushed on termination.
  """

  use GenServer

  require Logger

  @default_batch_size 10
  # milliseconds
  @default_batch_timeout 100

  # Client API

  @doc """
  Starts the CassetteWriter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Asynchronously writes an entry to a cassette.
  """
  def write_entry(cassette_path, entry) do
    GenServer.cast(__MODULE__, {:write_entry, cassette_path, entry})
  end

  @doc """
  Immediately flushes all pending writes for a specific cassette.
  """
  def flush_cassette(cassette_path) do
    GenServer.call(__MODULE__, {:flush_cassette, cassette_path})
  end

  @doc """
  Flushes all pending writes for all cassettes.
  """
  def flush_all do
    GenServer.call(__MODULE__, :flush_all)
  end

  @doc """
  Replaces an entire cassette with accumulated entries for :all mode.
  This ensures cassettes are only replaced when we have the complete new data.
  """
  def replace_cassette_for_all_mode(cassette_path) do
    GenServer.call(__MODULE__, {:replace_cassette_all_mode, cassette_path})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    storage_backend = opts[:storage_backend] || Reqord.Storage.FileSystem

    config = %{
      batch_size: opts[:batch_size] || @default_batch_size,
      batch_timeout: opts[:batch_timeout] || @default_batch_timeout,
      storage_backend: storage_backend
    }

    state = %{
      # %{cassette_path => [entry, ...]}
      pending_writes: %{},
      # %{cassette_path => timer_ref}
      write_timers: %{},
      config: config
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:write_entry, cassette_path, entry}, state) do
    # Add entry to pending writes
    pending = Map.get(state.pending_writes, cassette_path, [])
    updated_pending = [entry | pending]

    state = put_in(state.pending_writes[cassette_path], updated_pending)

    # Check if we should write immediately (batch size reached)
    state =
      if length(updated_pending) >= state.config.batch_size do
        flush_cassette_internal(cassette_path, state)
      else
        # Set or reset the batch timer
        reset_timer(cassette_path, state)
      end

    {:noreply, state}
  end

  @impl true
  def handle_call({:flush_cassette, cassette_path}, _from, state) do
    state = flush_cassette_internal(cassette_path, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:flush_all, _from, state) do
    state =
      Enum.reduce(Map.keys(state.pending_writes), state, fn path, acc ->
        flush_cassette_internal(path, acc)
      end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:replace_cassette_all_mode, cassette_path}, _from, state) do
    case Map.get(state.pending_writes, cassette_path) do
      nil ->
        # No pending entries, nothing to replace
        {:reply, :ok, state}

      [] ->
        # Empty pending entries, nothing to replace
        {:reply, :ok, state}

      entries ->
        # We have entries to replace the cassette with
        state = cancel_timer(cassette_path, state)

        # Sort entries by timestamp (oldest first)
        sorted_entries =
          Enum.sort_by(entries, fn entry ->
            Map.get(entry, "recorded_at", 0)
          end)

        # Replace entire cassette using delete + create operations
        result =
          replace_cassette_atomically(cassette_path, sorted_entries, state.config.storage_backend)

        # Clear pending writes for this cassette
        state =
          state
          |> put_in([:pending_writes, cassette_path], [])
          |> Map.update!(:write_timers, &Map.delete(&1, cassette_path))

        {:reply, result, state}
    end
  end

  @impl true
  def handle_info({:batch_timeout, cassette_path}, state) do
    state = flush_cassette_internal(cassette_path, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Flush all pending writes on termination
    Enum.each(Map.keys(state.pending_writes), fn path ->
      flush_cassette_internal(path, state)
    end)

    :ok
  end

  # Private functions

  defp flush_cassette_internal(cassette_path, state) do
    case Map.get(state.pending_writes, cassette_path) do
      nil ->
        state

      [] ->
        state

      entries ->
        # Cancel any existing timer
        state = cancel_timer(cassette_path, state)

        # Sort entries by timestamp (oldest first)
        sorted_entries =
          Enum.sort_by(entries, fn entry ->
            Map.get(entry, "recorded_at", 0)
          end)

        # Write entries to storage
        write_entries_to_storage(cassette_path, sorted_entries, state.config.storage_backend)

        # Clear pending writes for this cassette
        state
        |> put_in([:pending_writes, cassette_path], [])
        |> Map.update!(:write_timers, &Map.delete(&1, cassette_path))
    end
  end

  defp write_entries_to_storage(cassette_path, entries, storage_backend) do
    Enum.each(entries, fn entry ->
      case storage_backend.write_entry(cassette_path, entry) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to write entry to #{cassette_path}: #{inspect(reason)}")
      end
    end)
  end

  defp replace_cassette_atomically(cassette_path, entries, storage_backend) do
    # Never replace with empty entries - this would delete cassette content
    if Enum.empty?(entries) do
      Logger.warning(
        "Attempted to replace cassette #{cassette_path} with empty entries - operation skipped"
      )

      :ok
    else
      # Simple approach: delete existing cassette, then write all entries
      # This follows the basic operations principle
      with :ok <- storage_backend.delete_cassette(cassette_path),
           :ok <- storage_backend.ensure_path_exists(cassette_path) do
        # Write each entry using the basic write_entry operation
        Enum.reduce_while(entries, :ok, fn entry, :ok ->
          case storage_backend.write_entry(cassette_path, entry) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      else
        {:error, reason} ->
          Logger.error("Failed to replace cassette #{cassette_path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp reset_timer(cassette_path, state) do
    # Cancel existing timer if any
    state = cancel_timer(cassette_path, state)

    # Start new timer
    timer_ref =
      Process.send_after(
        self(),
        {:batch_timeout, cassette_path},
        state.config.batch_timeout
      )

    put_in(state.write_timers[cassette_path], timer_ref)
  end

  defp cancel_timer(cassette_path, state) do
    case Map.get(state.write_timers, cassette_path) do
      nil ->
        state

      timer_ref ->
        Process.cancel_timer(timer_ref)
        Map.update!(state, :write_timers, &Map.delete(&1, cassette_path))
    end
  end
end
