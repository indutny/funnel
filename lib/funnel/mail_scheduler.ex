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
  def schedule(_server, mail) do
    Logger.info("New mail #{inspect(mail)}")
    # TODO(indutny): Implement me
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
