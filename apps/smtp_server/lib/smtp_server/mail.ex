defmodule SMTPServer.Mail do
  @enforce_keys [:reverse_path, :max_size]
  defstruct [:reverse_path, :max_size, forward_paths: [], data: <<>>]

  @type t() :: %SMTPServer.Mail{
          reverse_path: String.t(),
          forward_paths: [String.t()],
          max_size: integer | nil,
          data: binary
        }

  def add_forward_path(mail, forward_path) do
    %SMTPServer.Mail{mail | forward_paths: [forward_path | mail.forward_paths]}
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
