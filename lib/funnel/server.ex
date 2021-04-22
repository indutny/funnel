defmodule Funnel.Server do
  use Task, restart: :permanent
  use TypedStruct

  require Logger

  typedstruct module: Config do
    field :local_domain, String.t(), default: "funnel.localhost"
    field :max_mail_size, non_neg_integer(), default: 30 * 1024 * 1024
    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000
    field :port, :inet.port_number(), default: 0

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias Funnel.Server.Protocol, as: Protocol

  @moduledoc """
  Server implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid(), map()}
  def start_link(config, _opts \\ []) do
    ref = make_ref()

    {:ok, pid} =
      :ranch.start_listener(ref, :ranch_tcp, [port: config.port], Protocol, %Protocol.Config{
        local_domain: config.local_domain,
        max_mail_size: config.max_mail_size,
        read_timeout: config.read_timeout,
        max_line_size: config.max_line_size
      })

    {addr, port} = :ranch.get_addr(ref)

    Logger.info("Accepting connections on " <> "#{:inet.ntoa(addr)}:#{port}")

    {:ok, pid, %{port: port}}
  end
end
