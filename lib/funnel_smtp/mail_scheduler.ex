defmodule FunnelSMTP.MailScheduler do
  alias FunnelSMTP.Mail

  @type t :: GenServer.server()
  @type impl :: {atom(), t()}
  @type forward_result ::
          {:ok, FunnelSMTP.forward_path()} | {:error, :not_found | term()}

  @callback schedule(t(), Mail.t()) :: :ok
  @callback allow_reverse_path?(t(), FunnelSMTP.reverse_path()) :: boolean()
  @callback map_forward_path(t(), FunnelSMTP.forward_path()) :: forward_result()

  @spec schedule(impl(), Mail.t()) :: :ok
  def schedule({implementation, server}, mail) do
    implementation.schedule(server, mail)
  end

  @spec allow_reverse_path?(impl(), FunnelSMTP.reverse_path()) :: boolean()
  def allow_reverse_path?({implementation, server}, email) do
    implementation.allow_reverse_path?(server, email)
  end

  @spec map_forward_path(impl(), FunnelSMTP.forward_path()) :: forward_result()
  def map_forward_path({implementation, server}, email) do
    implementation.map_forward_path(server, email)
  end
end
