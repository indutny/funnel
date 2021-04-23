defmodule FunnelSMTPTest.MockScheduler do
  use GenServer
  @behaviour FunnelSMTP.MailScheduler

  alias FunnelSMTP.Mail

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def pop(server) do
    GenServer.call(server, :pop)
  end

  # MailScheduler implementation

  @impl true
  def schedule(server, mail, trace) do
    GenServer.call(server, {:schedule, mail, trace})
  end

  @impl true
  def allow_reverse_path?(_, :null) do
    true
  end

  @impl true
  def allow_reverse_path?(_, "allowed@sender") do
    true
  end

  @impl true
  def allow_reverse_path?(_, _) do
    false
  end

  @impl true
  def map_forward_path(_, :postmaster) do
    {:ok, :postmaster}
  end

  @impl true
  def map_forward_path(_, m = "allowed@rcpt") do
    {:ok, m}
  end

  @impl true
  def map_forward_path(_, m = "second@rcpt") do
    {:ok, m}
  end

  @impl true
  def map_forward_path(_, _) do
    {:error, :not_found}
  end

  # GenServer implementation

  @impl true
  def init(:ok) do
    {:ok, :queue.new()}
  end

  @impl true
  def handle_call({:schedule, mail, trace}, _from, queue) do
    mail =
      Mail.add_trace(mail, %Mail.Trace{
        trace
        | # Just to make test outputs predictable
          timestamp: ~U[1984-02-16 07:06:40Z]
      })

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
