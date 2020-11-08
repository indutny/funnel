defmodule SMTPServer.Connection do
  use GenServer
  require Logger

  alias SMTPServer.Mail

  @type state() ::
          :handshake
          | :main
          | {:rcpt, Mail}
          | {:data, Mail, :crlf | :lf}
          | :shutdown

  @type line_response ::
          {:no_response, state()}
          | {:normal, state(), non_neg_integer(), String.t() | [String.t()]}
          | {:shutdown, non_neg_integer(), String.t()}

  # Public API

  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def handshake(pid) do
    GenServer.call(pid, :handshake)
  end

  def respond_to(pid, line) do
    GenServer.call(pid, {:line, line})
  end

  # GenServer implementation

  @impl true
  def init(config) do
    {:ok, {:handshake, config}}
  end

  @impl true
  def handle_call(:handshake, _from, s = {_state, config}) do
    {:reply, {:normal, 220, "Welcome to #{config.local_domain}"}, s}
  end

  @impl true
  def handle_call({:line, line}, _from, {state, config}) do
    Logger.debug("#{config.remote_domain} < #{String.trim_trailing(line)}")

    line =
      case state do
        {:data, _, _} ->
          line

        _ ->
          line
          |> SMTPProtocol.parse_command()
      end

    case handle_line(config, state, line) do
      {:no_response, new_state} ->
        {:reply, :no_response, {new_state, config}}

      {:response, new_state, code, response} ->
        {:reply, {:normal, code, response}, {new_state, config}}

      {:shutdown, code, response} ->
        {:reply, {:shutdown, code, response}, {:shutdown, config}}
    end
  end

  @spec handle_line(map(), state(), SMTPProtocol.command()) :: line_response()
  defp handle_line(config, state, line)

  defp handle_line(_, :handshake, {:rset, "", _}) do
    {:response, :handshake, 250, "OK"}
  end

  defp handle_line(_, _, {:rset, "", _}) do
    {:response, :main, 250, "OK"}
  end

  defp handle_line(_, state, {:noop, "", _}) do
    {:response, state, 250, "OK"}
  end

  defp handle_line(_, _, {:quit, "", _}) do
    {:shutdown, 221, "OK"}
  end

  defp handle_line(_, :handshake, {:helo, _domain, _}) do
    {:response, :main, 250, "OK"}
  end

  defp handle_line(config, :handshake, {:ehlo, _domain, _}) do
    {:response, :main, 250,
     [
       "#{config.local_domain} greets #{config.remote_domain}",
       # TODO(indutny): STARTTLS
       "8BITMIME",
       "PIPELINING",
       "SIZE #{config.max_mail_size}",
       "SMTPUTF8"
     ]}
  end

  defp handle_line(_, :main, {:vrfy, _, _}) do
    # Not really supported
    {:response, :main, 252, "I will be happy to accept your message"}
  end

  defp handle_line(_, :main, {:help, _, _}) do
    # Not really supported
    {:response, :main, 214, "I'm so glad you asked. Check RFC 5321"}
  end

  defp handle_line(config, :main, {:mail_from, reverse_path, _}) do
    case SMTPProtocol.parse_mail_and_params(reverse_path, :mail) do
      {:ok, reverse_path, params} ->
        case receive_reverse_path(config, reverse_path, params) do
          {:ok, mail} ->
            {:response, {:rcpt, mail}, 250, "OK"}

          {:error, :max_size_exceeded} ->
            {:response, :main, 552, "Mail exceeds maximum allowed size"}
        end

      {:error, :unknown_param} ->
        {:response, :main, 555, "MAIL FROM parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, :main, 553, msg}
    end
  end

  defp handle_line(config, {:rcpt, mail}, {:rcpt_to, forward_path, _}) do
    case SMTPProtocol.parse_mail_and_params(forward_path, :rcpt) do
      {:ok, forward_path, params} ->
        {:ok, new_mail} = receive_forward_path(config, mail, forward_path, params)
        {:response, {:rcpt, new_mail}, 250, "OK"}

      {:error, :unknown_param} ->
        {:response, :main, 555, "RCPT TO parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, {:rcpt, mail}, 553, msg}
    end
  end

  defp handle_line(_, {:rcpt, mail}, {:data, "", trailing}) do
    if Enum.empty?(mail.forward_paths) do
      {:response, {:rcpt, mail}, 554, "No valid recipients"}
    else
      {:response, {:data, mail, trailing}, 354, "Start mail input; end with <CRLF>.<CRLF>"}
    end
  end

  defp handle_line(_, {:data, mail, :crlf}, ".\r\n") do
    if Mail.has_exceeded_size?(mail) do
      Logger.info("Mail size exceeded")
      {:response, :main, 552, "Mail exceeds maximum allowed size"}
    else
      Logger.info("Got new mail")
      :ok = process_mail(mail)
      {:response, :main, 250, "OK"}
    end
  end

  defp handle_line(_, {:data, mail, _}, data) do
    data =
      with "." <> stripped <- data do
        stripped
      end

    trailing =
      if String.ends_with?(data, "\r\n") do
        :crlf
      else
        :lf
      end

    {:no_response, {:data, Mail.add_data(mail, data), trailing}}
  end

  defp handle_line(_, state, {:data, "", _}) do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, {:rcpt_to, _, _}) do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, {:unknown, line}) do
    Logger.info("Unknown command #{line}")
    {:response, state, 502, "Command not implemented"}
  end

  defp handle_line(_, _, _) do
    {:shutdown, 451, "Server error"}
  end

  @spec receive_reverse_path(map(), String.t(), map()) ::
          {:ok, Mail}
          | {:error, atom()}
  defp receive_reverse_path(config, reverse_path, params) do
    # TODO(indutny): should we bother about possible 7-bit encoding?
    case Map.get(params, :size, config.max_mail_size) do
      size when size > config.max_mail_size ->
        {:error, :max_size_exceeded}

      max_size ->
        mail = %Mail{
          reverse_path: {reverse_path, params},
          max_size: max_size
        }

        {:ok, mail}
    end
  end

  @spec receive_forward_path(map(), Mail.t(), String.t(), map()) ::
          {:ok, Mail.t()}
          | {:error, atom()}
  defp receive_forward_path(_, mail, forward_path, params) do
    # TODO(indutny): check that `forward_path` is in allowlist
    # 550 - if no such user
    # should also disallow outgoing email (different domain) unless
    # authorized.
    # NOTE: Allow case-insensitive Postmaster
    {:ok, Mail.add_forward_path(mail, {forward_path, params})}
  end

  @spec process_mail(Mail.t()) :: :ok
  defp process_mail(mail) do
    mail = Mail.trim_trailing_crlf(mail)

    IO.inspect(mail)
    :ok
  end
end
