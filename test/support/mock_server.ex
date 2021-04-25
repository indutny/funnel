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

  def starttls() do
    GenServer.call(__MODULE__, :starttls)
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
    {:reply, :ok, {:accepted, :gen_tcp, accepted}}
  end

  @impl true
  def handle_call(:starttls, _from, {:accepted, :gen_tcp, socket}) do
    {:ok, secure} =
      :ssl.handshake(socket, [
        :binary,
        packet: :line,
        packet_size: @max_line_size,
        active: false,

        # TLS configuration
        versions: [:"tlsv1.2", :"tlsv1.3"],
        certfile: "priv/keys/cert.pem",
        keyfile: "priv/keys/key.pem",
        dhfile: "priv/keys/dh.pem",
        honor_cipher_order: true,
        ciphers: Funnel.get_ciphers()
      ])

    {:reply, :ok, {:accepted, :ssl, secure}}
  end

  @impl true
  def handle_call(:recv_line, _from, state = {:accepted, transport, socket}) do
    {:ok, line} = transport.recv(socket, 0)
    {:reply, line, state}
  end

  @impl true
  def handle_call({:send_line, line}, _from, state) do
    {:accepted, transport, socket} = state
    :ok = transport.send(socket, line <> "\r\n")
    {:reply, :ok, state}
  end
end
