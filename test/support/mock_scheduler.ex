defmodule FunnelSMTPTest.MockScheduler do
  use GenServer
  @behaviour FunnelSMTP.MailScheduler

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def pop(server) do
    GenServer.call(server, :pop)
  end

  # MailScheduler implementation

  @impl true
  def schedule(server, mail) do
    GenServer.call(server, {:schedule, mail})
  end

  @impl true
  def allow_path?(_, :mail_from, :null) do
    true
  end

  def allow_path?(_, :mail_from, "allowed@sender") do
    true
  end

  def allow_path?(_, :rcpt_to, :postmaster) do
    true
  end

  def allow_path?(_, :rcpt_to, "allowed@rcpt") do
    true
  end

  def allow_path?(_, :rcpt_to, "second@rcpt") do
    true
  end

  def allow_path?(_, _, _) do
    false
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
        {:reply, {:ok, mail}, queue}

      {:empty, queue} ->
        {:reply, {:error, :empty}, queue}
    end
  end
end
