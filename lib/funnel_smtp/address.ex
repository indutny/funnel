defmodule FunnelSMTP.Address do
  # Various small patterns
  @ipv6_hex ~S"[0-9a-fA-F]{1,4}"
  @let_dig ~S"[a-zA-Z0-9]"
  @ldh_str ~S"[a-zA-Z0-9\-]*" <> @let_dig
  @atext ~S"[a-zA-Z0-9!#$%&'*+\-/=?^_`{|}~]"
  @qtext_smtp ~S"[\x20-\x21\x23-x5b\x5d-\x7e]"
  @quoted_pair_smtp ~S"\x5c[\x20-\x7e]"
  @snum ~S"[0-9]{1,3}"
  @ipv4_address_literal @snum <> ~S"(?:\." <> @snum <> ~S"){3}"
  @dcontent ~S"[\x21-\x5a\x5e-\x7e]"

  @doc """
  Generates regex matching an email address.

  ## Examples

      iex> "<a@b.com>" =~ FunnelSMTP.Address.compile()
      true
  """
  @spec compile() :: Regex.t()
  def compile() do
    sub_domain = @let_dig <> optional(@ldh_str)
    domain = sub_domain <> ~S"(?:\." <> sub_domain <> ~S")*"

    atom = @atext <> ~S"*"
    dot_string = atom <> ~S"(?:\." <> atom <> ~S")*"

    qcontent_smtp = either([@qtext_smtp, @quoted_pair_smtp])
    quoted_string = ~S"\"(?:" <> qcontent_smtp <> ~S")*\""

    ipv6_address_literal = ~S"IPv6:" <> name("ipv6_addr", ipv6_addr())

    standardized_tag = @ldh_str
    general_address_literal = standardized_tag <> ~S":" <> @dcontent <> ~S"+"

    address_literal =
      ~S"\[" <>
        either([
          name("ipv4_addr", @ipv4_address_literal),
          ipv6_address_literal,
          name("general_addr", general_address_literal)
        ]) <> "\]"

    local_part =
      either([
        name("dot_string", dot_string),
        name("quoted_string", quoted_string)
      ])

    mailbox =
      name("local_part", local_part) <>
        ~S"@" <>
        either([
          name("domain", domain),
          name("addr", address_literal)
        ])

    at_domain = ~S"@" <> domain
    a_d_l = at_domain <> ~S"(?:," <> at_domain <> ~S")*"

    path =
      ~S"<" <>
        optional(name("a_d_l", a_d_l) <> ":") <>
        name("mailbox", mailbox) <> ">"

    Regex.compile!(~S"^" <> path <> ~S"$")
  end

  @doc """
  Generates regex matching an IPv6 address.

  ## Examples

      iex> "1:12:123:1234:5:6:7:8" =~ FunnelSMTP.Address.compile_ipv6_addr()
      true

      iex> "1:12::5:6:7:8" =~ FunnelSMTP.Address.compile_ipv6_addr()
      true

      iex> "::1" =~ FunnelSMTP.Address.compile_ipv6_addr()
      true

      iex> "::127.0.0.1" =~ FunnelSMTP.Address.compile_ipv6_addr()
      true

      iex> "1:2:3:4:5:6:127.0.0.1" =~ FunnelSMTP.Address.compile_ipv6_addr()
      true

  ## Invalid examples

      iex> "1:2:3:4::5:6:7:8" =~ FunnelSMTP.Address.compile_ipv6_addr()
      false

      iex> "1:2:3:4:5:6:7" =~ FunnelSMTP.Address.compile_ipv6_addr()
      false

      iex> "1:2:3:4:5:127.0.0.1" =~ FunnelSMTP.Address.compile_ipv6_addr()
      false
  """
  @spec compile_ipv6_addr() :: Regex.t()
  def compile_ipv6_addr() do
    Regex.compile!(~S"^" <> ipv6_addr() <> ~S"$")
  end

  defp ipv6_addr() do
    ipv6_full = @ipv6_hex <> ~S"(?::" <> @ipv6_hex <> ~S"){7}"

    ipv6_comp =
      0..6
      |> Enum.map(&ipv6_comp_gen/1)
      |> either

    ipv6v4_full =
      @ipv6_hex <>
        ~S"(?::" <>
        @ipv6_hex <>
        ~S"){5}" <>
        ~S":" <> @ipv4_address_literal

    ipv6v4_comp =
      0..4
      |> Enum.map(&ipv6_comp_gen(&1, 4, @ipv6_hex, ":"))
      |> either

    ipv6v4_comp = ipv6v4_comp <> @ipv4_address_literal

    either([ipv6_full, ipv6_comp, ipv6v4_full, ipv6v4_comp])
  end

  @doc """
  Generates named group.

  ## Examples

      iex> FunnelSMTP.Address.name("name", "group")
      "(?<name>group)"
  """
  def name(n, pattern) do
    ~S"(?<" <> n <> ~S">" <> pattern <> ~S")"
  end

  @doc """
  Generates regex string matching either of the elements of the list.

  ## Examples

      iex> FunnelSMTP.Address.either(["a", "b"])
      "(?:a|b)"
  """
  def either(list) do
    ~S"(?:" <> Enum.join(list, ~S"|") <> ")"
  end

  @doc """
  Generates regex string matching optional value.

  ## Examples

      iex> FunnelSMTP.Address.optional("a")
      "(?:a)?"
  """
  def optional(val) do
    ~S"(?:" <> val <> ~S")?"
  end

  @doc """
  Generates compressed ipv6 pattern.

  ## Examples

      iex> FunnelSMTP.Address.ipv6_comp_gen(0, 6, "@")
      "::(?:@|@(?::@){5})?"

      iex> FunnelSMTP.Address.ipv6_comp_gen(2, 6, "@")
      "(?:@|@(?::@){1})?::(?:@|@(?::@){3})?"
  """
  def ipv6_comp_gen(left_count, total \\ 6, group \\ @ipv6_hex, postfix \\ "") do
    ipv6_repeat_group(left_count, group) <>
      ~S"::" <>
      ipv6_repeat_group(total - left_count, group, postfix)
  end

  @doc """
  Repeats ipv6 hex group.

  ## Examples:

      iex> FunnelSMTP.Address.ipv6_repeat_group(0, "@")
      ""

      iex> FunnelSMTP.Address.ipv6_repeat_group(0, "@", ":")
      ""

      iex> FunnelSMTP.Address.ipv6_repeat_group(1, "@")
      "(?:@)?"

      iex> FunnelSMTP.Address.ipv6_repeat_group(1, "@", "p")
      "(?:@p)?"

      iex> FunnelSMTP.Address.ipv6_repeat_group(4, "@")
      "(?:@|@(?::@){3})?"

      iex> FunnelSMTP.Address.ipv6_repeat_group(4, "@", "p")
      "(?:@p|@(?::@){3}p)?"
  """
  def ipv6_repeat_group(count, group \\ @ipv6_hex, postfix \\ "") do
    case count do
      0 ->
        ""

      1 ->
        optional(group <> postfix)

      n when n > 1 ->
        either([
          group <> postfix,
          group <>
            ~S"(?::" <>
            group <>
            ~S"){" <>
            to_string(n - 1) <>
            ~S"}" <> postfix
        ]) <> "?"
    end
  end
end
