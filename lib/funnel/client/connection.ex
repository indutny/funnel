defmodule Funnel.Client.Connection do
  use TypedStruct

  @type config() :: Funnel.Client.Config
  @type t() :: {config(), :gen_tcp.socket()}

  @behaviour FunnelSMTP.Connection

  @spec connect(config()) :: {:ok, t()} | {:error, term()}
  def connect(config) do
    opts = [
      :binary,
      packet: :line,
      packet_size: config.max_line_size,
      active: false
    ]

    with {:ok, socket} <-
           :gen_tcp.connect(
             String.to_charlist(config.host),
             config.port,
             opts,
             config.connect_timeout
           ) do
      {:ok, {config, socket}}
    end
  end

  # FunnelSMTP.Connection implementation

  @impl FunnelSMTP.Connection
  def send({_, socket}, line) do
    :gen_tcp.send(socket, line)
  end

  @impl FunnelSMTP.Connection
  def recv_line({config, socket}) do
    :gen_tcp.recv(socket, 0, config.read_timeout)
  end

  @impl FunnelSMTP.Connection
  def close({_, socket}) do
    :gen_tcp.close(socket)
  end
end
