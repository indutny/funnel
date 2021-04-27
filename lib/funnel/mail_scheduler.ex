defmodule Funnel.MailScheduler do
  use GenServer
  use TypedStruct

  require Logger

  alias FunnelSMTP.DKIM

  @behaviour FunnelSMTP.MailScheduler

  typedstruct module: Config do
    field :allow_list, module(), default: Funnel.AllowList
    field :forward_list, module(), default: Funnel.ForwardList
    field :local_domain, String.t(), default: "funnel.local"
    field :dkim_selector, String.t(), default: "static"
    field :dkim_private_key, String.t(), default: "priv/keys/dkim-private.pem"
  end

  @type options :: [GenServer.options() | {:config, Config.t()}]
  @magic_hash "FUN"

  alias FunnelSMTP.Mail
  alias Funnel.Client

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, %Config{})
    GenServer.start_link(__MODULE__, config, opts)
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
  def schedule(server, mail, trace) do
    mail = GenServer.call(server, {:sign_and_trace, mail, trace})

    # TODO(indutny): put email into database, and send asynchronously
    # NOTE: Until async send is here - it must be sent outside of GenServer to
    # allow concurrency
    :ok = forward_mail(mail.forward, mail)
  end

  @impl true
  def allow_reverse_path?(_, :null) do
    true
  end

  @impl true
  def allow_reverse_path?(server, email) do
    GenServer.call(server, {:allow_reverse_path?, email})
  end

  @impl true
  def map_forward_path(_, :postmaster) do
    {:ok, :postmaster}
  end

  @impl true
  def map_forward_path(server, email) do
    GenServer.call(server, {:map_forward_path, email})
  end

  # GenServer implementation

  @impl true
  def init(config) do
    {:ok, dkim} =
      DKIM.start_link(%DKIM.Config{
        private_key: config.dkim_private_key,
        domain: config.local_domain,
        selector: config.dkim_selector
      })

    {:ok, {config, dkim}}
  end

  @impl true
  def handle_call({:allow_reverse_path?, email}, _from, state = {config, _}) do
    {:reply, config.allow_list.contains?(email), state}
  end

  @impl true
  def handle_call({:map_forward_path, email}, _from, state = {config, _}) do
    {:reply, config.forward_list.map(email), state}
  end

  @impl true
  def handle_call({:sign_and_trace, mail, trace}, _from, state) do
    {config, dkim} = state

    mail =
      Mail.add_trace(mail, trace)
      |> Mail.wrap_srs(@magic_hash, config.local_domain)

    mail =
      DKIM.sign(dkim, mail, [
        "date",
        "subject",
        "to"
      ])

    {:reply, mail, state}
  end
end
