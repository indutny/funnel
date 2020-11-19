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
    opts = [
      :binary,
      packet: :line,
      packet_size: config.max_line_size,
      active: false
    ]

    with {:ok, socket} <-
           :gen_tcp.connect(
             config.host,
             config.port,
             opts,
             config.connect_timeout
           ) do
      {:ok, {config, socket}}
    end
  end

  # FunnelSMTP.Connection implementation

  @impl FunnelSMTP.Connection
  def send(server, line) do
    GenServer.call(server, {:send, line})
  end

  @impl FunnelSMTP.Connection
  def recv_line(server) do
    GenServer.call(server, :recv_line)
  end

  @impl FunnelSMTP.Connection
  def close(server) do
    GenServer.call(server, :close)
  end

  # GenServer implementation

  @impl GenServer
  def handle_call({:send, line}, _from, s = {_, socket}) do
    reply = :gen_tcp.send(socket, line)
    {:reply, reply, s}
  end

  @impl GenServer
  def handle_call(:recv_line, _from, s = {config, socket}) do
    reply = :gen_tcp.recv(socket, 0, config.read_timeout)
    {:reply, reply, s}
  end

  @impl GenServer
  def handle_call(:close, _from, s = {_config, socket}) do
    reply = :gen_tcp.close(socket)
    {:reply, reply, s}
  end
end
