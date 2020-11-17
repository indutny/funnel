defmodule Funnel.MailScheduler do
  use GenServer
  require Logger

  @behaviour FunnelSMTP.MailScheduler

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  # MailScheduler implementation

  @impl true
  def schedule(server, mail) do
    Logger.info("New mail #{inspect(mail)}")
  end

  @impl true
  def pop(server) do
    {:error, :not_implemented}
  end

  @impl true
  def allow_path?(_, :mail_from, :null) do
    # TODO(indutny): apply extra size limits
    true
  end

  def allow_path?(_, :mail_from, email) do
    Funnel.AllowList.contains?(email)
  end

  def allow_path?(_, :rcpt_to, :postmaster) do
    # TODO(indutny): apply extra size limits
    true
  end

  def allow_path?(_, :rcpt_to, email) do
    Funnel.ForwardList.contains?(email)
  end

  # GenServer implementation

  @impl true
  def init(:ok) do
    {:ok, :queue.new()}
  end

  @impl true
  def handle_call({:schedule, mail}, _from, queue) do
    {:reply, :ok, :queue.in(mail, queue)}
  end

  @impl true
  def handle_call(:pop, _from, queue) do
    case :queue.out(queue) do
      {{:value, mail}, queue} ->
        {:reply, {:mail, mail}, queue}

      {:empty, queue} ->
        {:reply, :empty, queue}
    end
  end
end
