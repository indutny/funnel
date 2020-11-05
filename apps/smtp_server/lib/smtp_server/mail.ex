defmodule SMTPServer.Mail do
  @enforce_keys [:reverse_path, :max_size]
  defstruct [:reverse_path, :max_size, forward_paths: [], data: <<>>]

  alias SMTPServer.Mail

  @type t() :: %Mail{
          reverse_path: {String.t(), SMTPProtocol.reverse_params()},
          forward_paths: [{String.t(), SMTPProtocol.forward_params()}],
          max_size: integer | nil,
          data: binary
        }

  @doc """
  Adds new forward path to the mail.
  """
  def add_forward_path(mail, forward_path) do
    %Mail{mail | forward_paths: [forward_path | mail.forward_paths]}
  end

  @doc """
  Appends data to the mail's buffer.
  """
  def add_data(mail, data) do
    if has_exceeded_size?(mail) do
      mail
    else
      %Mail{mail | data: mail.data <> data}
    end
  end

  def has_exceeded_size?(mail) do
    # NOTE: taking trailing CRLF in account and allow a bit of leeway.
    byte_size(mail.data) > mail.max_size + 2 + 1024
  end

  @doc """
  Returns byte size of the mail's data.
  """
  def data_size(mail) do
    byte_size(mail.data)
  end

  def has_trailing_crlf?(mail) do
    size = byte_size(mail.data)
    "\r\n" == binary_part(mail.data, size, -min(2, size))
  end

  @doc """
  Removes trailing CRLF from the mail's data.
  """
  def trim_trailing_crlf(mail) do
    true = has_trailing_crlf?(mail)
    trimmed_data = binary_part(mail.data, 0, byte_size(mail.data) - 2)

    %Mail{
      mail
      | data: trimmed_data
    }
  end
end
