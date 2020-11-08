defmodule SMTPProtocol.Mail do
  use TypedStruct

  typedstruct do
    field :reverse, {String.t(), SMTPProtocol.reverse_params()}, enforce: true
    field :forward, [{String.t(), SMTPProtocol.forward_params()}], default: []
    field :data, binary(), default: <<>>
  end

  alias SMTPProtocol.Mail

  @doc """
  Create new empty mail
  """
  @spec new(String.t(), SMTPProtocol.reverse_params()) :: t()
  def new(reverse_path, reverse_params \\ %{}) do
    %Mail{
      reverse: {reverse_path, reverse_params}
    }
  end

  @doc """
  Adds new forward path to the mail.
  """
  @spec add_forward(t(), String.t(), SMTPProtocol.forward_params()) :: t()
  def add_forward(mail, forward_path, forward_params \\ %{}) do
    %Mail{
      mail
      | forward: [{forward_path, forward_params} | mail.forward]
    }
  end

  @doc """
  Appends data to the mail's buffer.
  """
  @spec add_data(t(), binary()) :: t()
  def add_data(mail, data) do
    %Mail{mail | data: mail.data <> data}
  end

  @doc """
  Returns byte size of the mail's data.
  """
  @spec data_size(t()) :: non_neg_integer()
  def data_size(mail) do
    byte_size(mail.data)
  end

  @doc """
  Removes trailing CRLF from the mail's data.
  """
  @spec trim_trailing_crlf(t()) :: t()
  def trim_trailing_crlf(mail) do
    true = String.ends_with?(mail.data, "\r\n")
    trimmed_data = binary_part(mail.data, 0, byte_size(mail.data) - 2)

    %Mail{
      mail
      | data: trimmed_data
    }
  end
end
