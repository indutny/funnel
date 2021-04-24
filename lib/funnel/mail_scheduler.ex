defmodule Funnel.MailScheduler do
  use GenServer
  require Logger

  @behaviour FunnelSMTP.MailScheduler

  alias FunnelSMTP.Mail
  alias Funnel.Client

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec forward_mail([{Mail.forward_path(), Mail.forward_params()}], Mail.t()) :: :ok
  defp forward_mail([{forward_path, _} | rest], mail) do
    Logger.info("Forwarding mail to #{forward_path}")

    [_, host] = String.split(forward_path, "@", parts: 2)

    {:ok, client} =
      Client.start_link(%Client.Config{
        host: host,
        local_domain: Application.fetch_env!(:funnel, :smtp_domain)
      })

    :ok = Client.connect(client)
    :ok = Client.send(client, mail)
    :ok = Client.close(client)

    forward_mail(rest, mail)
  end

  defp forward_mail([], _mail) do
    :ok
  end

  # MailScheduler implementation

  @impl true
  def schedule(_server, mail, trace) do
    mail = Mail.add_trace(mail, trace)

    # TODO(indutny): put email into database, and send asynchronously
    :ok = forward_mail(mail.forward, mail)
  end

  @impl true
  def allow_reverse_path?(_, :null) do
    true
  end

  @impl true
  def allow_reverse_path?(_, email) do
    Funnel.AllowList.contains?(email)
  end

  @impl true
  def map_forward_path(_, :postmaster) do
    {:ok, :postmaster}
  end

  @impl true
  def map_forward_path(_, email) do
    Funnel.ForwardList.map(email)
  end

  # GenServer implementation

  @impl true
  def init(state) do
    {:ok, state}
  end
end
