defmodule Funnel.Client.Connection do
  use TypedStruct
  use GenServer

  @type config() :: Funnel.Client.Config.t()
  @type t() :: FunnelSMTP.Connection.t()

  @behaviour FunnelSMTP.Connection

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec connect(t(), config()) :: :ok | {:error, atom()}
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

    opts = [
      :binary,
      packet: :line,
      packet_size: config.max_line_size,
      active: false
    ]

    ssl_opts =
      opts ++
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
                verify_fun: {
                  &:ssl_verify_hostname.verify_fun/3,
                  [{:check_hostname, host}]
                },
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
    {:ok, secure} = :ssl.handshake(socket, ssl_opts)
    {:reply, :ok, {config, ssl_opts, :ssl, secure}}
  end

  @impl true
  def handle_call({:send, line}, _from, state = {_, _, transport, socket}) do
    {:reply, transport.send(socket, line), state}
  end

  @impl true
  def handle_call(:recv_line, _from, state = {config, _, transport, socket}) do
    {:reply, transport.recv(socket, 0, config.read_timeout), state}
  end

  @impl true
  def handle_call(:close, _from, {_, _, transport, socket}) do
    {:stop, :closed, transport.close(socket), :not_connected}
  end
end
