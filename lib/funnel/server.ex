defmodule Funnel.Server do
  use Task, restart: :permanent
  use TypedStruct

  require Logger

  alias Funnel.Server.Protocol
  alias FunnelSMTP.MailScheduler

  typedstruct module: Config do
    field :local_domain, String.t(), default: "funnel.localhost"
    field :max_mail_size, non_neg_integer(), default: 30 * 1024 * 1024
    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000
    field :port, :inet.port_number(), default: 0
    field :keyfile, String.t(), enforce: true
    field :certfile, String.t(), enforce: true
    field :dhfile, String.t(), enforce: true
    field :mail_scheduler, MailScheduler.impl(), enforce: true
  end

  @moduledoc """
  Server implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid(), map()}
  def start_link(config, _opts \\ []) do
    ref = make_ref()

    ranch_opts = [
      port: config.port
    ]

    ssl_opts = [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      # TODO(indutny): do we need to cache these?
      certfile: config.certfile,
      keyfile: config.keyfile,
      dhfile: config.dhfile,
      honor_cipher_order: true,
      ciphers: Funnel.get_ciphers()
    ]

    protocol_config = %Protocol.Config{
      local_domain: config.local_domain,
      max_mail_size: config.max_mail_size,
      read_timeout: config.read_timeout,
      mail_scheduler: config.mail_scheduler,
      ssl_opts: ssl_opts
    }

    {:ok, pid} = :ranch.start_listener(ref, :ranch_tcp, ranch_opts, Protocol, protocol_config)

    {addr, port} = :ranch.get_addr(ref)

    Logger.info("Accepting connections on " <> "#{:inet.ntoa(addr)}:#{port}")

    {:ok, pid, %{port: port, ref: ref}}
  end

  @spec close(reference()) :: :ok | {:error, any()}
  def close(ref) do
    :ranch.stop_listener(ref)
  end
end
