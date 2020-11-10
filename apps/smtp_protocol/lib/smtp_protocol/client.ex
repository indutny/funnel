defmodule SMTPProtocol.Client do
  @moduledoc """
  SMTP Client connection implementation.
  """

  use TypedStruct
  require Logger

  alias SMTPProtocol.Connection
  alias SMTPProtocol.Mail

  typedstruct module: Config, enforce: true do
    field :local_domain, :inet.hostname()
  end

  @spec handshake(Config.t(), Connection.t()) :: :ok | {:error, String.t()}
  def handshake(_config, remote) do
    with {:ok, line} <- Connection.recv_line(remote) do
      IO.inspect(line)
      :ok
    end
  end

  @spec send(Config.t(), Connection.t(), Mail.t()) :: :ok | {:error, String.t()}
  def send(config, remote, mail) do
    :ok
  end
end
