defmodule FunnelSMTP.Mail do
  use TypedStruct

  @max_forward_count 100

  @type forward_path :: FunnelSMTP.forward_path()
  @type reverse_path :: FunnelSMTP.reverse_path()
  @type forward_params :: FunnelSMTP.forward_params()
  @type reverse_params :: FunnelSMTP.reverse_params()

  typedstruct do
    field :reverse, {reverse_path(), reverse_params()}, enforce: true
    field :forward, [{forward_path(), forward_params()}], default: []
    field :data, binary(), enforce: true
  end

  typedstruct module: Trace do
    field :remote_domain, String.t(), enforce: true
    field :remote_addr, String.t(), enforce: true
    field :local_domain, String.t(), enforce: true
    field :local_addr, String.t(), enforce: true
    field :timestamp, DateTime.t(), default: DateTime.utc_now()
  end

  alias FunnelSMTP.Mail

  @doc """
  Create new empty mail
  """
  @spec new(reverse_path(), reverse_params()) :: t()
  def new(reverse_path, reverse_params \\ %{}, data \\ "") do
    %Mail{
      reverse: {reverse_path, reverse_params},
      data: data
    }
  end

  @doc """
  Adds new forward path to the mail.
  """
  @spec add_forward(t(), forward_path(), forward_params()) ::
          {:ok, t()} | {:error, :forward_count_exceeded}
  def add_forward(mail, forward_path, forward_params \\ %{}) do
    if length(mail.forward) < @max_forward_count do
      mail = %Mail{
        mail
        | forward: [{forward_path, forward_params} | mail.forward]
      }

      {:ok, mail}
    else
      {:error, :forward_count_exceeded}
    end
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

      iex> mail = FunnelSMTP.Mail.new("a@b.com", %{}, "hello\r\n\r\n")
      ...>        |> FunnelSMTP.Mail.trim_trailing_crlf()
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

      iex> FunnelSMTP.Mail.new("a@b.com", %{}, "ohai")
      ...> |> FunnelSMTP.Mail.has_8bitdata?()
      false

      iex> FunnelSMTP.Mail.new("a@b.com", %{}, "こんにちは")
      ...> |> FunnelSMTP.Mail.has_8bitdata?()
      true
  """
  @spec has_8bitdata?(t()) :: boolean()
  def has_8bitdata?(mail) do
    mail.data
    |> :binary.bin_to_list()
    |> Enum.any?(&(&1 > 0x7F))
  end

  @doc """
  Checks if mail's reverse path is empty.

  ## Examples

      iex> FunnelSMTP.Mail.new(:null)
      ...> |> FunnelSMTP.Mail.is_anonymous?()
      true

      iex> FunnelSMTP.Mail.new("a@b.com")
      ...> |> FunnelSMTP.Mail.is_anonymous?()
      false
  """
  @spec is_anonymous?(t()) :: boolean()
  def is_anonymous?(mail) do
    case mail.reverse do
      {:null, _} -> true
      _ -> false
    end
  end

  @doc """
  Add tracing information to email.
  """
  @spec add_trace(t(), Trace.t()) :: t()
  def add_trace(mail, trace) do
    {reverse_path, _} = mail.reverse
    extended_from = trace.remote_domain <> " (" <> trace.remote_addr <> ")"
    extended_by = trace.local_domain <> " (" <> trace.local_addr <> ")"

    return_path = "Return-Path: <" <> reverse_path <> ">"

    received =
      "Received: from " <>
        extended_from <>
        "\r\n" <>
        "          by " <>
        extended_by <>
        ";\r\n" <>
        "          " <> FunnelSMTP.format_date(trace.timestamp)

    header = return_path <> "\r\n" <> received <> "\r\n"

    %Mail{mail | data: header <> mail.data}
  end
end
