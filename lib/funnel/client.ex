defmodule Funnel.Client do
  use GenServer
  use TypedStruct

  typedstruct module: Config do
    field :remote_domain, :inet.hostname(), ensure: true
    field :local_domain, :inet.hostname(), default: "funnel.localhost"

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

    smtp_remote = nil
    SMTPClient.start_link(smtp_config, smtp_remote)

    {:ok, config}
  end
end
