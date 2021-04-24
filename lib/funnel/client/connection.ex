defmodule Funnel.Client.Connection do
  use TypedStruct

  @type config() :: Funnel.Client.Config
  @type t() :: {config(), :ssl.socket()}

  @behaviour FunnelSMTP.Connection

  @spec connect(config()) :: {:ok, t()} | {:error, term()}
  def connect(config) do
    port = config.port
    connect_timeout = config.connect_timeout

    {lookup_fun, lookup_args} = config.lookup_fun
    {:ok, resolved} = apply(lookup_fun, lookup_args ++ [config.host])
    host = String.to_charlist(resolved)
    IO.inspect(host)

    opts = [
      :binary,
      packet: :line,
      packet_size: config.max_line_size,
      active: false,

      # TLS configuration
      versions: [:"tlsv1.2", :"tlsv1.3"],
      ciphers: Funnel.get_ciphers(),
      server_name_indication: host,
      reuse_sessions: false
    ]

    opts =
      case config.insecure do
        false ->
          [
            opts
            | [
                verify_fun: {
                  &:ssl_verify_hostname.verify_fun/3,
                  [{:check_hostname, host}]
                },
                verify: :verify_peer
              ]
          ]

        true ->
          opts
      end

    with {:ok, socket} <- :ssl.connect(host, port, opts, connect_timeout) do
      {:ok, {config, socket}}
    end
  end

  # FunnelSMTP.Connection implementation

  @impl FunnelSMTP.Connection
  def send({_, socket}, line) do
    :ssl.send(socket, line)
  end

  @impl FunnelSMTP.Connection
  def recv_line({config, socket}) do
    :ssl.recv(socket, 0, config.read_timeout)
  end

  @impl FunnelSMTP.Connection
  def close({_, socket}) do
    :ssl.close(socket)
  end
end
