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
    if byte_size(mail.data) >= mail.max_size do
      # Discard whole data on overflow
      %Mail{mail | data: <<>>}
    else
      %Mail{mail | data: mail.data <> data}
    end
  end

  @doc """
  Returns byte size of the mail's data.
  """
  def data_size(mail) do
    byte_size(mail.data)
  end

  @doc """
  Removes trailing CRLF/LF from the mail's data.
  """
  def trim_trailing_crlf(mail) do
    size = byte_size(mail.data)

    tail = binary_part(mail.data, size, -min(2, size))

    trimmed_data =
      case tail do
        "\r\n" -> binary_part(mail.data, 0, size - 2)
        <<_, ?\n>> -> binary_part(mail.data, 0, size - 1)
        _ -> mail.data
      end

    %Mail{
      mail
      | data: trimmed_data
    }
  end
end
