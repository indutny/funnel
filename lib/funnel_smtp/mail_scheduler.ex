defmodule FunnelSMTP.MailScheduler do
  alias FunnelSMTP.Mail

  @type t :: GenServer.server()
  @type impl :: {atom(), t()}
  @type side :: :mail_from | :rcpt_to

  @callback schedule(t(), Mail.t()) :: :ok
  @callback pop(t()) :: {:ok, Mail.t()} | {:error, atom()}
  @callback allow_path?(t(), side(), String.t()) :: boolean()

  @spec schedule(impl(), Mail.t()) :: :ok
  def schedule({implementation, server}, mail) do
    implementation.schedule(server, mail)
  end

  @spec pop(impl()) :: {:ok, Mail.t()} | {:error, atom()}
  def pop({implementation, server}) do
    implementation.pop(server)
  end

  @spec allow_path?(impl(), side(), FunnelSMTP.mail_path()) :: boolean()
  def allow_path?({implementation, server}, side, email) do
    implementation.allow_path?(server, side, email)
  end
end
