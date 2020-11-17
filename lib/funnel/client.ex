defmodule Funnel.Client do
  use Task
  use TypedStruct

  typedstruct module: Config do
    field :local_domain, :inet.hostname(), default: "funnel.localhost"
    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000
    field :port, non_neg_integer(), default: 0

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias FunnelSMTP.Client, as: SMTPClient

  @moduledoc """
  Client implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid()}
  def start_link(config, _opts \\ []) do
    Task.start_link(Funnel.Client, :connect, [config])
  end

  @spec connect(Config.t()) :: nil
  def connect(config) do
  end
end
