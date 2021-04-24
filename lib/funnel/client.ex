defmodule Funnel.Client do
  use GenServer
  use TypedStruct

  alias FunnelSMTP.Mail
  alias Funnel.Client.Connection

  @type t :: GenServer.server()

  typedstruct module: Config do
    field :host, String.t(), ensure: true
    field :port, :inet.port_number(), default: 25
    field :local_domain, String.t(), default: "funnel.localhost"

    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000

    # 1 minute
    field :connect_timeout, timeout(), default: 60 * 1000

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512

    field :insecure, boolean(), default: false
  end

  alias FunnelSMTP.Client, as: SMTPClient

  @moduledoc """
  Client implementation.
  """

  @spec start_link(Config.t(), [term()]) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @spec start(Config.t(), [term()]) :: GenServer.on_start()
  def start(config, opts \\ []) do
    GenServer.start(__MODULE__, config, opts)
  end

  @spec connect(t()) :: :ok | {:error, term()}
  def connect(client) do
    GenServer.call(client, :connect, :infinity)
  end

  @spec send(t(), Mail.t(), timeout()) :: :ok | {:error, term()}
  def send(client, mail, timeout \\ 5000) do
    GenServer.call(client, {:send, mail}, timeout)
  end

  # GenServer implementation

  @impl true
  def init(config) do
    {:ok, {:not_connected, config}}
  end

  @impl true
  def handle_call(:connect, _from, {:not_connected, config}) do
    smtp_config = %SMTPClient.Config{
      local_domain: config.local_domain
    }

    # TODO(indutny): connect to SSL port first and only then to default one.
    {:ok, conn} = Connection.connect(config)
    conn = {Funnel.Client.Connection, conn}

    {:ok, smtp} = SMTPClient.start_link(smtp_config, conn)

    :ok = SMTPClient.handshake(smtp)

    {:reply, :ok, {:connected, config, smtp}}
  end

  @impl true
  def handle_call({:send, mail}, _from, s = {:connected, _, smtp}) do
    {:reply, SMTPClient.send(smtp, mail), s}
  end
end
