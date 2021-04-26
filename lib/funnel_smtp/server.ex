defmodule FunnelSMTP.Server do
  @moduledoc """
  SMTP Server connection implementation. Receives line input from remote end
  and generates responses to be sent back.
  """

  use GenServer
  use TypedStruct

  require Logger

  alias FunnelSMTP.Mail
  alias FunnelSMTP.MailScheduler
  alias FunnelSMTP.Server.Config

  typedstruct module: Config, enforce: true do
    field :local_domain, String.t()
    field :local_addr, String.t()
    field :remote_domain, String.t()
    field :remote_addr, String.t()
    field :challenge_url, String.t()
    field :max_anonymous_mail_size, non_neg_integer(), default: 1024
    field :max_mail_size, non_neg_integer()
    field :mail_scheduler, MailScheduler.impl()

    field :mode, :insecure | :secure, default: :insecure
  end

  @type t :: GenServer.server()

  @typep state() ::
           :handshake
           | :main
           | {:rcpt, Mail.t()}
           | {:data, Mail.t(), :crlf | :lf}
           | :shutdown

  @type response() ::
          :no_response
          | {:normal | :shutdown | :starttls, non_neg_integer(), String.t() | [String.t()]}

  @type line() :: String.t()

  @type parsed_line() :: FunnelSMTP.command() | String.t() | {:unknown, String.t()}

  @typep line_response ::
           {:no_response, state()}
           | {:response, state(), non_neg_integer(), String.t() | [String.t()]}
           | {:response | :starttls, state(), non_neg_integer(), String.t() | [String.t()],
              Config.t()}
           | {:shutdown, non_neg_integer(), String.t()}

  @max_command_line_size 512
  @max_text_line_size 1000

  # Public API

  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @spec handshake(t()) :: response()
  def handshake(server) do
    GenServer.call(server, :handshake)
  end

  @spec respond_to(t(), line()) :: response()
  def respond_to(server, line) do
    GenServer.call(server, {:line, line})
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
    if Logger.enabled?(self()) do
      Logger.debug(
        "[server] #{config.remote_domain} " <>
          "< #{String.trim_trailing(line)}"
      )
    end

    response =
      case parse_line(state, line) do
        {:ok, line} ->
          case handle_line(config, state, line) do
            {:no_response, new_state} ->
              {:reply, :no_response, {new_state, config}}

            {:response, new_state, code, response} ->
              {:reply, {:normal, code, response}, {new_state, config}}

            {:response, new_state, code, response, new_config} ->
              {:reply, {:normal, code, response}, {new_state, new_config}}

            {:starttls, new_state, code, response, new_config} ->
              {:reply, {:starttls, code, response}, {new_state, new_config}}

            {:shutdown, code, response} ->
              {:reply, {:shutdown, code, response}, {:shutdown, config}}
          end

        {:error, code, response} ->
          {:reply, {:shutdown, code, response}, {:shutdown, config}}
      end

    with true <- Logger.enabled?(self()),
         {_, response, _} <- response do
      Logger.debug("[server] #{config.remote_domain} > #{inspect(response)}")
    end

    response
  end

  @spec parse_line(state(), line()) ::
          {:ok, parsed_line()} | {:error, non_neg_integer(), String.t()}
  defp parse_line({:data, _, :crlf}, line) when line == ".\r\n" do
    {:ok, line}
  end

  defp parse_line({:data, _, _}, line) do
    line =
      with "." <> stripped <- line do
        stripped
      end

    if byte_size(line) > @max_text_line_size do
      {:error, 500, "Text line too long"}
    else
      {:ok, line}
    end
  end

  defp parse_line(_, line) when byte_size(line) > @max_command_line_size do
    {:error, 500, "Command line too long"}
  end

  defp parse_line(_, line) do
    {:ok, FunnelSMTP.parse_command(line)}
  end

  @spec handle_line(Config.t(), state(), parsed_line()) :: line_response()
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

  defp handle_line(config, :handshake, {:ehlo, domain, _}) do
    greeting = "#{config.local_domain} greets #{domain} (#{config.remote_addr})"

    extensions = [
      "8BITMIME",
      "PIPELINING",
      "SIZE #{config.max_mail_size}"
    ]

    extensions =
      case config.mode do
        :insecure ->
          extensions ++ ["STARTTLS"]

        :secure ->
          extensions
      end

    {:response, :main, 250, [greeting] ++ extensions, %Config{config | remote_domain: domain}}
  end

  defp handle_line(config = %{mode: :insecure}, :main, {:starttls, "", _}) do
    {:starttls, :handshake, 220, "Go ahead", %Config{config | mode: :secure}}
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
    case FunnelSMTP.parse_mail_and_params(reverse_path, :mail) do
      {:ok, reverse_path, params} ->
        case receive_reverse_path(config, reverse_path, params) do
          {:ok, mail} ->
            {:response, {:rcpt, mail}, 250, "OK"}

          {:error, :max_size_exceeded} ->
            {:response, :main, 552, "Mail exceeds maximum allowed size"}

          {:error, :access_denied} ->
            challenge_url = "#{config.challenge_url}?source=#{reverse_path}"
            {:response, :main, 550, "Please solve a challenge to proceed: #{challenge_url}"}
        end

      {:error, :unknown_param} ->
        {:response, :main, 555, "MAIL FROM parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, :main, 553, msg}
    end
  end

  defp handle_line(config, s = {:rcpt, mail}, {:rcpt_to, forward_path, _}) do
    result =
      with {:ok, forward_path, params} <-
             FunnelSMTP.parse_mail_and_params(forward_path, :rcpt) do
        receive_forward_path(config, mail, forward_path, params)
      end

    case result do
      {:ok, new_mail} ->
        {:response, {:rcpt, new_mail}, 250, "OK"}

      {:error, :forward_count_exceeded} ->
        {:response, s, 452, "Too many recipients"}

      {:error, :access_denied} ->
        {:response, s, 550, "Mailbox not found"}

      {:error, :unknown_param} ->
        {:response, s, 555, "RCPT TO parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, s, 553, msg}
    end
  end

  defp handle_line(_, {:rcpt, mail}, {:data, "", trailing}) do
    if Enum.empty?(mail.forward) do
      {:response, {:rcpt, mail}, 554, "No valid recipients"}
    else
      {:response, {:data, mail, trailing}, 354, "Start mail input; end with <CRLF>.<CRLF>"}
    end
  end

  defp handle_line(config, {:data, mail, :crlf}, ".\r\n") do
    max_mail_size =
      if Mail.is_anonymous?(mail) do
        config.max_anonymous_mail_size
      else
        config.max_mail_size
      end

    if Mail.data_size(mail) > max_mail_size + 2 do
      Logger.info("Mail size exceeded")
      {:response, :main, 552, "Mail exceeds maximum allowed size"}
    else
      Logger.info("Got new mail")

      mail = Mail.trim_trailing_crlf(mail)

      :ok =
        MailScheduler.schedule(config.mail_scheduler, mail, %Mail.Trace{
          local_domain: config.local_domain,
          local_addr: config.local_addr,
          remote_domain: config.remote_domain,
          remote_addr: config.remote_addr
        })

      {:response, :main, 250, "OK"}
    end
  end

  defp handle_line(config, {:data, mail, _}, data) do
    trailing =
      if String.ends_with?(data, "\r\n") do
        :crlf
      else
        :lf
      end

    new_size = Mail.data_size(mail) + byte_size(data)
    soft_limit = config.max_mail_size + 2 + 1024

    mail =
      if new_size > soft_limit do
        mail
      else
        Mail.add_data(mail, data)
      end

    {:no_response, {:data, mail, trailing}}
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
          {:ok, Mail.t()}
          | {:error, :access_denied | :max_size_exceeded}
  defp receive_reverse_path(config, reverse_path, params) do
    is_allowed? =
      MailScheduler.allow_reverse_path?(
        config.mail_scheduler,
        reverse_path
      )

    cond do
      not is_allowed? ->
        Logger.info("Access denied to MAIL FROM:#{inspect(reverse_path)}")
        {:error, :access_denied}

      Map.get(params, :size, config.max_mail_size) > config.max_mail_size ->
        Logger.info("Max size exceeded MAIL FROM:#{inspect(reverse_path)}")
        {:error, :max_size_exceeded}

      true ->
        mail = Mail.new(reverse_path, params)
        {:ok, mail}
    end
  end

  @spec receive_forward_path(map(), Mail.t(), String.t(), map()) ::
          {:ok, Mail.t()}
          | {:error, :access_denied | :forward_count_exceeded | term()}
  defp receive_forward_path(config, mail, forward_path, params) do
    maybe_forward_path =
      MailScheduler.map_forward_path(
        config.mail_scheduler,
        forward_path
      )

    case maybe_forward_path do
      {:ok, forward_path} ->
        Mail.add_forward(mail, forward_path, params)

      {:error, :not_found} ->
        Logger.info(
          "Access denied for RCPT TO:#{inspect(forward_path)}, " <>
            "mail=#{inspect(mail)}"
        )

        {:error, :access_denied}

      err = {:error, _} ->
        err
    end
  end
end
