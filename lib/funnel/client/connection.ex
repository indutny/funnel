defmodule Funnel.Client.Connection do
  use GenServer
  use TypedStruct

  @type config() :: Funnel.Client.Config

  @behaviour FunnelSMTP.Connection

  @spec start_link(config(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  # GenServer implementation

  @impl GenServer
  def init(config) do
    socket = nil
    {:ok, {config, socket}}
  end

  # FunnelSMTP.Connection implementation

  @impl FunnelSMTP.Connection
  def send(_server, _line) do
    {:error, "Not implemented"}
  end

  @impl FunnelSMTP.Connection
  def recv_line(_server) do
    {:error, "Not implemented"}
  end

  @impl FunnelSMTP.Connection
  def close(_server) do
    :ok
  end
end
