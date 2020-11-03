defmodule SMTPServer.Mail do
  @enforce_keys [:from, :to, :max_size]
  defstruct [:from, :to, :max_size, data: <<>>]

  def add_recipient(mail, mailbox) do
    %SMTPServer.Mail{mail | to: [mailbox | mail.to]}
  end

  def add_data(mail, data) do
    if byte_size(mail.data) >= mail.max_size do
      # Discard whole data on overflow
      %SMTPServer.Mail{mail | data: <<>>}
    else
      %SMTPServer.Mail{mail | data: mail.data <> data}
    end
  end

  def data_size(mail) do
    byte_size(mail.data)
  end
end
