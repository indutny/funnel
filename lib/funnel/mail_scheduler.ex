defmodule Funnel.MailScheduler do
  use GenServer
  @behaviour FunnelSMTP.MailScheduler

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  # MailScheduler implementation

  @impl true
  def schedule(server, mail) do
    IO.inspect(mail)
    GenServer.call(server, {:schedule, mail})
  end

  @impl true
  def pop(server) do
    GenServer.call(server, :pop)
  end

  @impl true
  def allow_path?(_, side, email) do
    case side do
      :mail_from ->
        Funnel.AllowList.contains?(email)

      :rcpt_to ->
        # TODO(indutny): implement me
        true
    end
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
