defmodule Funnel.Client.Connection do
  use GenServer

  @behaviour FunnelSMTP.Connection

  @spec start_link(:gen_tcp.socket(), GenServer.options()) ::
          GenServer.on_start()
  def start_link(socket, opts \\ []) do
    GenServer.start_link(__MODULE__, socket, opts)
  end

  # GenServer implementation

  @impl GenServer
  def init(socket) do
    {:ok, socket}
  end

  # FunnelSMTP.Connection implementation

  @impl FunnelSMTP.Connection
  def send(_server, _line) do
    {:error, :not_implemented}
  end

  @impl FunnelSMTP.Connection
  def recv_line(_server) do
    {:error, :not_implemented}
  end

  @impl FunnelSMTP.Connection
  def close(_server) do
    :ok
  end
end
