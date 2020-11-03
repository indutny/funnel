defmodule SMTPServer.Mail do
  @enforce_keys [:from, :to]
  defstruct [:from, :to, :data]

  def add_recipient(mail, mailbox) do
    %SMTPServer.Mail{mail | to: [mailbox | mail.to]}
  end
end
