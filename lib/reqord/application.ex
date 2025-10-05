defmodule Reqord.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the CassetteWriter for async cassette writing
      {Reqord.CassetteWriter,
       [
         storage_backend:
           Application.get_env(:reqord, :storage_backend, Reqord.Storage.FileSystem),
         batch_size: Application.get_env(:reqord, :writer_batch_size, 10),
         batch_timeout: Application.get_env(:reqord, :writer_batch_timeout, 100)
       ]}
    ]

    opts = [strategy: :one_for_one, name: Reqord.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
