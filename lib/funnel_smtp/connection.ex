defmodule FunnelSMTP.Connection do
  @type t :: GenServer.server()
  @type impl :: {atom(), t()}

  @callback starttls(t()) :: :ok | {:error, any()}
  @callback send(t(), String.t()) :: :ok | {:error, any()}
  @callback recv_line(t()) :: {:ok, String.t()} | {:error, any()}
  @callback close(t()) :: :ok | {:error, any()}

  @spec starttls(impl()) :: :ok | {:error, any()}
  def starttls({implementation, server}) do
    implementation.starttls(server)
  end

  @spec send(impl(), String.t()) :: :ok | {:error, any()}
  def send({implementation, server}, line) do
    implementation.send(server, line)
  end

  @spec recv_line(impl()) :: {:ok, String.t()} | {:error, any()}
  def recv_line({implementation, server}) do
    implementation.recv_line(server)
  end

  @spec close(impl()) :: :ok | {:error, any()}
  def close({implementation, server}) do
    implementation.close(server)
  end
end
