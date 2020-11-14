defmodule SMTPProtocol.Client do
  @moduledoc """
  SMTP Client connection implementation.
  """

  use GenServer

  use TypedStruct
  require Logger

  alias SMTPProtocol.Connection
  alias SMTPProtocol.Mail

  @type t :: GenServer.server()

  typedstruct module: Config do
    field :local_domain, :inet.hostname(), enforce: true
    field :extensions, [String.t()], default: []
  end

  # Public API

  @spec start_link(Config.t(), Connection.impl(), GenServer.options()) ::
          GenServer.on_start()
  def start_link(config, remote, opts \\ []) do
    GenServer.start_link(__MODULE__, {config, remote}, opts)
  end

  @spec handshake(t()) :: :ok | {:error, String.t()}
  def handshake(server) do
    GenServer.call(server, :handshake)
  end

  @spec send(t(), Mail.t()) :: :ok | {:error, String.t()}
  def send(server, mail) do
    GenServer.call(server, {:send, mail})
  end

  @spec quit(t()) :: :ok | {:error, String.t()}
  def quit(server) do
    GenServer.call(server, :quit)
  end

  # GenServer implementation

  @impl true
  def init({config, remote}) do
    {:ok, {config, remote}}
  end

  @impl true
  def handle_call(:handshake, _from, {config, remote}) do
    {:ok, 220, _} = receive_response(remote)

    Connection.send(remote, "EHLO #{config.local_domain}\r\n")

    extensions =
      case receive_response(remote) do
        {:ok, 250, [_greeting | lines]} ->
          lines

        {:ok, _, _} ->
          Connection.send(remote, "HELO #{config.local_domain}\r\n")
          {:ok, 250, _} = receive_response(remote)

          # No extensions
          []

        err ->
          err
      end

    extensions = Enum.map(extensions, &SMTPProtocol.parse_extension/1)

    config = %Config{config | extensions: extensions}

    {:reply, :ok, {config, remote}}
  end

  @impl true
  def handle_call({:send, mail}, _from, s = {config, remote}) do
    {from, _} = mail.reverse

    if Mail.has_8bitdata?(mail) do
    end

    Connection.send(remote, "MAIL FROM:<#{from}>\r\n")
    {:ok, 250, _} = receive_response(remote)

    {:reply, :ok, s}
  end

  @impl true
  def handle_call(:quit, _from, s = {config, remote}) do
    {:reply, Connection.close(remote), s}
  end

  # Private helpers

  defp receive_response(remote) do
    with {:ok, line} <- Connection.recv_line(remote),
         {:ok, {code, message, order}} <- SMTPProtocol.parse_response(line) do
      response = {:ok, code, [message]}

      case order do
        :last ->
          response

        :not_last ->
          with {:ok, next_code, messages} <- receive_response(remote) do
            if next_code != code do
              {:error, "Multi-line response code mismatch #{code} != #{next_code}"}
            else
              {:ok, code, [message | messages]}
            end
          end
      end
    end
  end
end
