defmodule SMTPServer.MailScheduler do
  use GenServer

  alias SMTPProtocol.Mail

  @type t :: GenServer.server()

  @spec start_link(GenServer.options()) :: {:ok, t()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec schedule(t(), Mail.t()) :: nil
  def schedule(_server, mail) do
    IO.inspect(mail)
  end

  @impl true
  def init(:ok) do
    {:ok, :ok}
  end
end
