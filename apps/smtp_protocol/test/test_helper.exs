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

  @impl true
  def close(_server) do
    :ok
  end

  # GenServer implementation

  @impl true
  def init(remote) do
    {:ok,
     %{
       state: :ready,
       remote: remote,
       responses: [Server.handshake(remote)]
     }}
  end

  @impl true
  def handle_call({:send, line}, _from, state) do
    response = Server.respond_to(state.remote, line)
    {:reply, :ok, %{state | responses: state.responses ++ [response]}}
  end

  @impl true
  def handle_call(:recv_line, _from, state = %{state: :shutdown}) do
    {:reply, {:error, :closed}, state}
  end

  @impl true
  def handle_call(:recv_line, _from, state) do
    case pop_response(state.responses) do
      {:ok, response, new_responses} ->
        {:reply, {:ok, response}, %{state | responses: new_responses}}

      err ->
        {:reply, err, state}
    end
  end

  # Private helpers

  defp pop_response([:no_response | tail]) do
    pop_response(tail)
  end

  defp pop_response([{_mode, code, [last_line]} | tail]) do
    {:ok, "#{code} #{last_line}\r\n", tail}
  end

  defp pop_response([{mode, code, [line | more_lines]} | tail]) do
    {:ok, "#{code}-#{line}\r\n", [{mode, code, more_lines} | tail]}
  end

  defp pop_response([{mode, code, last_line} | tail]) when is_bitstring(last_line) do
    pop_response([{mode, code, [last_line]} | tail])
  end

  defp pop_response([]) do
    raise "No response to pop!"
  end
end

ExUnit.start()
