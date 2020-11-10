defmodule SMTPProtocolTest.MockScheduler do
  use GenServer
  @behaviour SMTPProtocol.MailScheduler

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  # MailScheduler implementation

  @impl true
  def schedule(server, mail) do
    GenServer.call(server, {:schedule, mail})
  end

  @impl true
  def pop(server) do
    GenServer.call(server, :pop)
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

defmodule SMTPProtocolTest.MockConnection do
  use GenServer

  @behaviour SMTPProtocol.Connection

  alias SMTPProtocol.Server

  @spec start_link(Server.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(remote, opts \\ []) do
    GenServer.start_link(__MODULE__, remote, opts)
  end

  # Connection implementation

  @impl true
  def send(server, line) do
    GenServer.call(server, {:send, line})
  end

  @impl true
  def recv_line(server) do
    GenServer.call(server, :recv_line)
  end

  # GenServer implementation

  @impl true
  def init(remote) do
    {:ok, remote}
  end

  @impl true
  def handle_call({:send, line}, _from, remote) do
    response = Server.respond_to(remote, line)
    IO.inspect(response)
    {:reply, :ok, remote}
  end

  @impl true
  def handle_call(:recv_line, _from, remote) do
    {:reply, {:error, :implement_me}, remote}
  end
end

ExUnit.start()
