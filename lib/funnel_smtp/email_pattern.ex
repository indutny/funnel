defmodule FunnelSMTP.EmailPattern do
  @ipv6_hex ~S"[0-9a-fA-F]{1,4}"

  @doc """
  Generates regex matching email.

  ## Examples

      iex> "a@b.com" =~ FunnelSMTP.EmailPattern.generate()
      true

      iex> "a@b." =~ FunnelSMTP.EmailPattern.generate()
      false

      iex> "" =~ FunnelSMTP.EmailPattern.generate()
      false
  """
  def generate() do
    let_dig = ~S"[a-zA-Z0-9]"
    ldh_str = ~S"[a-zA-Z\-]*" <> let_dig
    sub_domain = let_dig <> ~S"(?:" <> ldh_str <> ~S")?"
    domain = sub_domain <> ~S"(?:\." <> sub_domain <> ~S")*"

    atext = ~S"[a-zA-Z0-9!#$%&'*+\-/=?^_`{|}~]"
    atom = atext <> ~S"*"
    dot_string = atom <> ~S"(?:\." <> atom <> ~S")*"

    qtext_smtp = ~S"[\x20-\x21\x23-x5b\x5d-\x7e]"
    quoted_pair_smtp = ~S"\x5c[\x20-\x7e]"
    qcontent_smtp = either([qtext_smtp, quoted_pair_smtp])
    quoted_string = ~S"\"(?:" <> qcontent_smtp <> ~S")*\""

    snum = ~S"\d{1,3}"
    ipv4_address_literal = snum <> ~S"(?:\." <> snum <> ~S"){3}"

    ipv6_full = @ipv6_hex <> ~S"(?::" <> @ipv6_hex <> ~S"){7}"
    ipv6_comp = 0..6
                |> Enum.map(&ipv6_comp_gen/1)
                |> either

    ipv6v4_full = @ipv6_hex <> ~S"(?::" <> @ipv6_hex <> ~S"){5}" <>
      ~S":" <> ipv4_address_literal
    ipv6v4_comp = 0..4
                  |> Enum.map(&ipv6_comp_gen(&1, 4, @ipv6_hex, ":"))
                  |> either
    ipv6v4_comp = ipv6v4_comp <> ipv4_address_literal

    ipv6_addr = either([ipv6_full, ipv6_comp, ipv6v4_full, ipv6v4_comp])
    ipv6_address_literal = ~S"IPv6:" <> ipv6_addr

    dcontent = ~S"[\x21-\x5a\x5e-\x7e]"
    standardized_tag = ldh_str
    general_address_literal = standardized_tag <> ~S":" <> dcontent <> ~S"+"

    address_literal = ~S"\[" <> either([
      ipv4_address_literal,
      ipv6_address_literal,
      general_address_literal,
    ]) <> "\]"

    local_part = either([dot_string, quoted_string])

    mailbox = name("local_part", local_part) <> ~S"@" <> either([
      name("domain", domain),
      name("address_literal", address_literal),
    ])

    at_domain = ~S"@" <> domain
    a_d_l = at_domain <> ~S"(?:," <> at_domain <> ~S")*"

    path = ~S"(?:" <> name("a_d_l", a_d_l) <> ~S":)?" <>
      name("mailbox", mailbox)

    {:ok, re} = Regex.compile(~S"^" <> path <> ~S"$")
    re
  end

  @doc """
  Generates named group.

  ## Examples

      iex> FunnelSMTP.EmailPattern.name("name", "group")
      "(?<name>group)"
  """
  def name(n, pattern) do
    ~S"(?<" <> n <> ~S">" <> pattern <> ~S")"
  end

  @doc """
  Generates regex string matching either of the elements of the list.

  ## Examples

      iex> FunnelSMTP.EmailPattern.either(["a", "b"])
      "(?:a|b)"
  """
  def either(list) do
    ~S"(?:" <> Enum.join(list, ~S"|") <> ")"
  end

  @doc """
  Generates compressed ipv6 pattern.

  ## Examples

      iex> FunnelSMTP.EmailPattern.ipv6_comp_gen(0, 6, "@")
      "::(?:@|@(?::@){5})"

      iex> FunnelSMTP.EmailPattern.ipv6_comp_gen(2, 6, "@")
      "(?:@|@(?::@){1})::(?:@|@(?::@){3})"
  """
  def ipv6_comp_gen(left_count, total \\ 6, group \\ @ipv6_hex,
                    postfix \\ "") do
    ipv6_repeat_group(left_count, group) <> ~S"::" <>
      ipv6_repeat_group(total - left_count, group, postfix)
  end

  @doc """
  Repeats ipv6 hex group.

  ## Examples:

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(0, "@")
      ""

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(0, "@", ":")
      ""

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(1, "@")
      "(?:@)?"

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(1, "@", "p")
      "(?:@p)?"

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(4, "@")
      "(?:@|@(?::@){3})"

      iex> FunnelSMTP.EmailPattern.ipv6_repeat_group(4, "@", "p")
      "(?:@p|@(?::@){3}p)"
  """
  def ipv6_repeat_group(count, group \\ @ipv6_hex, postfix \\ "") do
    case count do
      0 ->
        ""
      1 ->
        ~S"(?:" <> group <> postfix <> ~S")?"
      n when n > 1 ->
        either([
          group <> postfix,
          group <> ~S"(?::" <> group <> ~S"){" <> to_string(n - 1) <>
            ~S"}" <> postfix,
        ])
    end
  end
end
