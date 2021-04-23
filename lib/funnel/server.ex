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
    field :keyfile, String.t(), enforce: true
    field :certfile, String.t(), enforce: true
    field :dhfile, String.t(), enforce: true
  end

  alias Funnel.Server.Protocol, as: Protocol

  @ciphers [
    {:ecdhe_ecdsa, :chacha20_poly1305, :aead, :sha256},
    {:ecdhe_rsa, :chacha20_poly1305, :aead, :sha256},
    {:ecdhe_ecdsa, :aes_256_gcm, :aead, :sha384},
    {:ecdhe_rsa, :aes_256_gcm, :aead, :sha384},
    {:ecdhe_ecdsa, :aes_256_cbc, :sha384, :sha384},
    {:ecdhe_rsa, :aes_256_cbc, :sha384, :sha384},
    {:ecdhe_ecdsa, :aes_128_gcm, :aead, :sha256},
    {:ecdhe_rsa, :aes_128_gcm, :aead, :sha256},
    {:ecdhe_ecdsa, :aes_128_cbc, :sha256, :sha256},
    {:ecdhe_rsa, :aes_128_cbc, :sha256, :sha256},
    {:dhe_rsa, :chacha20_poly1305, :aead, :sha256},
    {:dhe_rsa, :aes_256_gcm, :aead, :sha384},
    {:dhe_rsa, :aes_256_cbc, :sha256},
    {:dhe_rsa, :aes_128_gcm, :aead, :sha256},
    {:dhe_rsa, :aes_128_cbc, :sha256},
    {:any, :chacha20_poly1305, :aead, :sha256},
    {:any, :aes_256_gcm, :aead, :sha384},
    {:any, :aes_128_gcm, :aead, :sha256}
  ]

  @moduledoc """
  Server implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid(), map()}
  def start_link(config, _opts \\ []) do
    ref = make_ref()

    ranch_opts = [
      port: config.port,
      versions: [:"tlsv1.2", :"tlsv1.3"],
      certfile: config.certfile,
      keyfile: config.keyfile,
      dhfile: config.dhfile,
      honor_cipher_order: true,
      ciphers: @ciphers
    ]

    protocol_config = %Protocol.Config{
      local_domain: config.local_domain,
      max_mail_size: config.max_mail_size,
      read_timeout: config.read_timeout
    }

    {:ok, pid} = :ranch.start_listener(ref, :ranch_ssl, ranch_opts, Protocol, protocol_config)

    {addr, port} = :ranch.get_addr(ref)

    Logger.info("Accepting connections on " <> "#{:inet.ntoa(addr)}:#{port}")

    {:ok, pid, %{port: port}}
  end
end
