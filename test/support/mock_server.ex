defmodule FunnelTest.MockServer do
  use GenServer

  @max_line_size 1024

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get_port() do
    GenServer.call(__MODULE__, :get_port)
  end

  def accept() do
    GenServer.call(__MODULE__, :accept)
  end

  def recv_line() do
    GenServer.call(__MODULE__, :recv_line)
  end

  def send_line(line) do
    GenServer.call(__MODULE__, {:send_line, line})
  end

  # GenServer

  @impl true
  def init(:ok) do
    {:ok, socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :line,
        packet_size: @max_line_size,
        reuseaddr: true,
        active: false
      ])

    {:ok, {:listen, socket}}
  end

  @impl true
  def handle_call(:get_port, _from, state = {:listen, socket}) do
    {:ok, {_, actual_port}} = :inet.sockname(socket)
    {:reply, actual_port, state}
  end

  @impl true
  def handle_call(:accept, _from, {:listen, socket}) do
    {:ok, accepted} = :gen_tcp.accept(socket)
    :ok = :gen_tcp.close(socket)
    {:reply, :ok, {:accepted, accepted}}
  end

  @impl true
  def handle_call(:recv_line, _from, state = {:accepted, socket}) do
    {:ok, line} = :gen_tcp.recv(socket, 0)
    {:reply, line, state}
  end

  @impl true
  def handle_call({:send_line, line}, _from, state = {:accepted, socket}) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
    {:reply, :ok, state}
  end
end
