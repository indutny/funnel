defmodule SMTPProtocol.MailScheduler do
  alias SMTPProtocol.Mail

  @type t :: GenServer.server()

  @callback schedule(t(), Mail.t()) :: :ok
  @callback pop(t()) :: Mail.t() | :empty

  @spec schedule({:atom, t()}, Mail.t()) :: :ok
  def schedule({implementation, server}, mail) do
    implementation.schedule(server, mail)
  end

  @spec pop({:atom, t()}) :: :ok
  def pop({implementation, server}) do
    implementation.pop(server)
  end
end
