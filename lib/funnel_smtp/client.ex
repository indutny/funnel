defmodule FunnelSMTP.Client do
  @moduledoc """
  SMTP Client connection implementation.
  """

  use GenServer

  require Logger

  alias FunnelSMTP.Connection
  alias FunnelSMTP.Mail

  @type t :: GenServer.server()

  defmodule Config do
    use TypedStruct

    typedstruct do
      field :local_domain, String.t(), enforce: true

      # TODO(indutny): separate state struct
      field :extensions, [FunnelSMTP.extension()], default: []
      field :mode, :secure | :insecure, default: :insecure
    end

    @spec supports_8bit?(t()) :: boolean()
    def supports_8bit?(config) do
      Enum.any?(config.extensions, &(&1 == :mime8bit))
    end

    @spec supports_starttls?(t()) :: boolean()
    def supports_starttls?(config) do
      Enum.any?(config.extensions, &(&1 == :starttls))
    end

    @spec supports_size?(t()) :: boolean()
    def supports_size?(config) do
      Enum.any?(config.extensions, &match?({:size, _}, &1))
    end
  end

  # Public API

  @spec start_link(Config.t(), Connection.impl(), GenServer.options()) ::
          GenServer.on_start()
  def start_link(config, remote, opts \\ []) do
    GenServer.start_link(__MODULE__, {config, remote}, opts)
  end

  @spec handshake(t()) :: :ok | {:error, any()}
  def handshake(server) do
    GenServer.call(server, :handshake)
  end

  @spec send(t(), Mail.t()) :: :ok | {:error, any()}
  def send(server, mail) do
    GenServer.call(server, {:send, mail})
  end

  @spec quit(t()) :: :ok | {:error, any()}
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

    case do_handshake(config, remote) do
      {:ok, config} ->
        {:reply, :ok, {config, remote}}

      error ->
        {:reply, error, {config, remote}}
    end
  end

  @impl true
  def handle_call({:send, mail}, _from, s = {config, _remote}) do
    cond do
      Mail.has_8bitdata?(mail) and not Config.supports_8bit?(config) ->
        {:reply, {:error, "Server does not support 8BIT mail"}}

      true ->
        {:reply, do_send_mail(s, mail), s}
    end
  end

  @impl true
  def handle_call(:quit, _from, s = {_config, remote}) do
    Connection.send!(remote, "QUIT\r\n")
    {:ok, 221, _} = receive_response(remote)

    {:reply, Connection.close(remote), s}
  end

  # Private helpers

  @spec receive_response(Connection.t()) ::
          {:ok, non_neg_integer(), [String.t()]} | {:error, any()}
  defp receive_response(remote) do
    with {:ok, line} <- Connection.recv_line(remote),
         {:ok, {code, message, order}} <- FunnelSMTP.parse_response(line) do
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

  @spec do_send_mail({Config.t(), Connection.t()}, Mail.t()) ::
          :ok | {:error, any()}
  defp do_send_mail({config, remote}, mail) do
    {from, _params} = mail.reverse

    from = "MAIL FROM:<#{from}>"

    from =
      if Config.supports_size?(config) do
        from <> " SIZE=#{Mail.data_size(mail)}"
      else
        from
      end

    Connection.send!(remote, from <> "\r\n")
    {:ok, 250, _} = receive_response(remote)

    for {to, _params} <- mail.forward do
      Connection.send!(remote, "RCPT TO:<#{to}>\r\n")
      {:ok, 250, _} = receive_response(remote)
    end

    Connection.send!(remote, "DATA\r\n")
    {:ok, 354, _} = receive_response(remote)

    # NOTE: We validate that each line in `mail.data` is at most 1000 bytes
    # long (inluding trailing CRLF) in server.ex
    Connection.send!(remote, mail.data)

    # NOTE: Splitted in two to make tests happy.
    Connection.send!(remote, "\r\n")
    Connection.send!(remote, ".\r\n")
    {:ok, 250, _} = receive_response(remote)

    :ok
  end

  @spec starttls(Config.t(), Connection.t()) :: {:ok, Config.t()} | {:error, any()}
  defp starttls(config, remote) do
    Connection.send!(remote, "STARTTLS\r\n")

    case receive_response(remote) do
      {:ok, 220, _} ->
        with :ok <- Connection.starttls(remote) do
          config = %Config{config | mode: :secure}
          do_handshake(config, remote)
        end

      {:ok, code, reason} ->
        {:error, {:starttls_failure, code, reason}}
    end
  end

  @spec do_handshake(Config.t(), Connection.t()) :: {:ok, Config.t()} | {:error, any()}
  defp do_handshake(config, remote) do
    Connection.send!(remote, "EHLO #{config.local_domain}\r\n")

    extensions =
      case receive_response(remote) do
        {:ok, 250, [_greeting | lines]} ->
          lines

        {:ok, _, _} ->
          Connection.send!(remote, "HELO #{config.local_domain}\r\n")
          {:ok, 250, _} = receive_response(remote)

          # No extensions
          []

        err ->
          err
      end

    extensions = Enum.map(extensions, &FunnelSMTP.parse_extension/1)

    config = %Config{config | extensions: extensions}

    if Config.supports_starttls?(config) do
      case config.mode do
        :secure ->
          {:error, :starttls_after_handshake}

        :insecure ->
          starttls(config, remote)
      end
    else
      case config.mode do
        :secure ->
          {:ok, config}

        :insecure ->
          {:error, :starttls_not_supported}
      end
    end
  end
end
