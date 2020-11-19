defmodule FunnelSMTP.Connection do
  @type t :: term()
  @type impl :: {atom(), t()}

  @callback send(t(), String.t()) :: :ok | {:error, String.t()}
  @callback recv_line(t()) :: {:ok, String.t()} | {:error, String.t()}
  @callback close(t()) :: :ok

  @spec send(impl(), String.t()) :: :ok | {:error, String.t()}
  def send({implementation, server}, line) do
    implementation.send(server, line)
  end

  @spec recv_line(impl()) :: {:ok, String.t()} | {:error, String.t()}
  def recv_line({implementation, server}) do
    implementation.recv_line(server)
  end

  @spec close(impl()) :: :ok
  def close({implementation, server}) do
    implementation.close(server)
  end
end
