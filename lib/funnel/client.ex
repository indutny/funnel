defmodule Funnel.Client do
  use GenServer
  use TypedStruct

  alias FunnelSMTP.Mail

  @type t :: GenServer.server()

  typedstruct module: Config do
    @type domain :: :inet.hostname() | :inet.socket_address()

    field :host, domain(), ensure: true
    field :port, :inet.port_number(), default: 25
    field :local_domain, domain(), default: "funnel.localhost"

    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000

    # 1 minute
    field :connect_timoeut, timeout(), default: 60 * 1000

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias FunnelSMTP.Client, as: SMTPClient

  @moduledoc """
  Client implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid()}
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @spec start(Config.t(), [term()]) :: {:ok, pid()}
  def start(config, opts \\ []) do
    GenServer.start(__MODULE__, config, opts)
  end

  @spec send(t(), Mail.t()) :: :ok | {:error, String.t()}
  def send(client, mail) do
    GenServer.call(client, {:send, mail})
  end

  # GenServer implementation

  @impl true
  def init(config) do
    smtp_config = %SMTPClient.Config{
      local_domain: config.local_domain
    }

    {:ok, conn} = Funnel.Client.Connection.start_link(config)
    conn = {Funnel.Client.Connection, conn}

    {:ok, smtp} = SMTPClient.start_link(smtp_config, conn)

    {:ok, {config, smtp}}
  end

  @impl true
  def handle_call({:send, mail}, _from, s = {_, smtp}) do
    {:reply, SMTPClient.send(smtp, mail), s}
  end
end
