defmodule Funnel.SMTP.Mail do
  use TypedStruct

  typedstruct do
    field :reverse, {String.t(), Funnel.SMTP.reverse_params()}, enforce: true
    field :forward, [{String.t(), Funnel.SMTP.forward_params()}], default: []
    field :data, binary(), enforce: true
  end

  alias Funnel.SMTP.Mail

  @doc """
  Create new empty mail
  """
  @spec new(String.t(), Funnel.SMTP.reverse_params()) :: t()
  def new(reverse_path, reverse_params \\ %{}, data \\ "") do
    %Mail{
      reverse: {reverse_path, reverse_params},
      data: data
    }
  end

  @doc """
  Adds new forward path to the mail.
  """
  @spec add_forward(t(), String.t(), Funnel.SMTP.forward_params()) :: t()
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

  @doc ~S"""
  Removes trailing CRLF from the mail's data.

  ## Examples

      iex> mail = Funnel.SMTP.Mail.new("a@b.com", %{}, "hello\r\n\r\n")
      ...>        |> Funnel.SMTP.Mail.trim_trailing_crlf()
      iex> mail.data
      "hello\r\n"
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

  @doc """
  Checks if mail's data has characters with 8th bit set to 1.

  ## Examples

      iex> Funnel.SMTP.Mail.new("a@b.com", %{}, "ohai")
      ...> |> Funnel.SMTP.Mail.has_8bitdata?()
      false

      iex> Funnel.SMTP.Mail.new("a@b.com", %{}, "こんにちは")
      ...> |> Funnel.SMTP.Mail.has_8bitdata?()
      true
  """
  def has_8bitdata?(mail) do
    mail.data
    |> :binary.bin_to_list()
    |> Enum.any?(&(&1 > 0x7F))
  end
end