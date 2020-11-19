defmodule Funnel.Client do
  use GenServer
  use TypedStruct

  typedstruct module: Config do
    @type domain :: :inet.hostname() | :inet.socket_address()

    field :remote_domain, domain(), ensure: true
    field :local_domain, domain(), default: "funnel.localhost"

    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias FunnelSMTP.Client, as: SMTPClient

  @moduledoc """
  Client implementation.
  """

  @spec start(Config.t(), [term()]) :: {:ok, pid()}
  def start(config, opts \\ []) do
    GenServer.start(__MODULE__, config, opts)
  end

  # GenServer implementation

  @impl true
  def init(config) do
    smtp_config = %SMTPClient.Config{
      local_domain: config.local_domain
    }

    {:ok, conn} = Funnel.Client.Connection.start_link(config)
    conn = {Funnel.Client.Connection, conn}

    SMTPClient.start_link(smtp_config, conn)

    {:ok, config}
  end
end
