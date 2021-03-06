defmodule Funnel.Client.Connection do
  use TypedStruct
  use GenServer

  require Logger

  @type config() :: Funnel.Client.Config.t()
  @type t() :: FunnelSMTP.Connection.t()

  @behaviour FunnelSMTP.Connection

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec connect(t(), config()) :: :ok | {:error, any()}
  def connect(server, config) do
    GenServer.call(server, {:connect, config})
  end

  # FunnelSMTP.Connection implementation

  @impl true
  def starttls(server) do
    GenServer.call(server, :starttls)
  end

  @impl true
  def send(server, line) do
    GenServer.call(server, {:send, line})
  end

  @impl true
  def recv_line(server) do
    GenServer.call(server, :recv_line)
  end

  @impl true
  def close(server) do
    GenServer.call(server, :close)
  end

  # GenServer implementation

  @impl true
  def init(:ok) do
    {:ok, :not_connected}
  end

  @impl true
  def handle_call({:connect, config}, _from, :not_connected) do
    port = config.port
    connect_timeout = config.connect_timeout

    {lookup_fun, lookup_args} = config.lookup_fun
    {:ok, resolved} = apply(lookup_fun, lookup_args ++ [config.host])
    host = String.to_charlist(resolved)

    common_opts = [
      packet: :line,
      packet_size: config.max_line_size,
      active: false
    ]

    opts =
      [
        :binary
      ] ++ common_opts

    ssl_opts =
      common_opts ++
        [
          # TLS configuration
          versions: [:"tlsv1.2", :"tlsv1.3"],
          ciphers: Funnel.get_ciphers(),
          server_name_indication: host,
          reuse_sessions: false
        ]

    ssl_opts =
      case config.insecure do
        false ->
          [
            ssl_opts
            | [
                depth: 100,
                cacerts: Funnel.get_cacerts(),
                # TODO(indutny): do I need partial_chain here?
                verify: :verify_peer
              ]
          ]

        true ->
          ssl_opts
      end

    with {:ok, socket} <- :gen_tcp.connect(host, port, opts, connect_timeout) do
      {:reply, :ok, {config, ssl_opts, :gen_tcp, socket}}
    end
  end

  @impl true
  def handle_call(:starttls, _from, {config, ssl_opts, :gen_tcp, socket}) do
    Logger.debug("[client] #{config.host} - STARTTLS")

    {:ok, secure} = :ssl.connect(socket, ssl_opts)
    {:reply, :ok, {config, ssl_opts, :ssl, secure}}
  end

  @impl true
  def handle_call({:send, line}, _from, state) do
    {config, _, transport, socket} = state

    if Logger.enabled?(self()) do
      Logger.debug("[client] #{config.host} > #{String.trim_trailing(line)}")
    end

    {:reply, transport.send(socket, line), state}
  end

  @impl true
  def handle_call(:recv_line, _from, state = {config, _, transport, socket}) do
    line = transport.recv(socket, 0, config.read_timeout)

    with true <- Logger.enabled?(self()),
         {:ok, line} <- line do
      Logger.debug("[client] #{config.host} < #{String.trim_trailing(line)}")
    end

    {:reply, line, state}
  end

  @impl true
  def handle_call(:close, _from, {config, _, transport, socket}) do
    Logger.debug("[client] #{config.host} - CLOSE")
    {:stop, :normal, transport.close(socket), :not_connected}
  end
end
