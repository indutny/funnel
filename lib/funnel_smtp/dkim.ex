defmodule FunnelSMTP.DKIM do
  @moduledoc """
  DKIM Signatures.
  """

  use GenServer
  use TypedStruct

  alias FunnelSMTP.Mail

  typedstruct module: Config do
    field :private_key, :String.t(), enforce: true
    field :domain, :String.t(), enforce: true
    field :selector, :String.t(), enforce: true
  end

  typedstruct module: State do
    field :private_key, :public_key.private_key(), enforce: true
    field :domain, :String.t(), enforce: true
    field :selector, :String.t(), enforce: true
  end

  @type t :: GenServer.server()

  # Public API

  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc ~S"""
  Signs headers and body using DKIM private key.
  """
  @spec sign(t(), Mail.t(), [String.t(), ...]) :: {:ok, Mail.t()} | {:error, any()}
  def sign(server, mail, signed_headers) do
    GenServer.call(server, {:sign, mail, signed_headers})
  end

  # GenServer implementation

  @impl true
  def init(config) do
    pem = File.read!(config.private_key)
    [entry] = :public_key.pem_decode(pem)
    private_key = :public_key.pem_entry_decode(entry)

    {:ok,
     %State{
       private_key: private_key,
       domain: config.domain,
       selector: config.selector
     }}
  end

  @impl true
  def handle_call({:sign, mail, signed_headers}, _from, state) do
    [headers, body] = String.split(mail.data, "\r\n\r\n", parts: 2)

    headers = String.split(headers, ~r/\r\n(?!\s)/)

    simple_headers =
      headers
      |> Enum.map(fn header ->
        [name, _] = String.split(header, ":", parts: 2)

        {name |> String.trim() |> String.downcase(), header}
      end)

    simple_headers =
      signed_headers
      |> Enum.map(fn expected ->
        Enum.find(simple_headers, fn {actual, _} ->
          actual == expected
        end)
      end)
      |> Enum.filter(&(not is_nil(&1)))
      |> Enum.map(&elem(&1, 1))

    simple_body = String.replace(body, ~r/(\r\n)*$/, "\r\n")

    body_hash =
      :crypto.hash(:sha256, simple_body)
      |> :base64.encode()

    dkim_header = [
      "DKIM-Signature: v=1; a=rsa-sha256; c=simple/simple;",
      "                d=#{state.domain}; s=#{state.selector};",
      "                h=#{Enum.join(signed_headers, ":")};",
      "                bh=#{body_hash}",
      "                b="
    ]

    signature =
      (dkim_header ++ simple_headers)
      |> Enum.join("\r\n")
      |> :public_key.sign(:sha256, state.private_key)
      |> :base64.encode()
      |> chunkify
      |> Enum.join("\r\n")
      |> String.trim()

    {signature_field, dkim_header} = List.pop_at(dkim_header, -1)

    dkim_header = dkim_header ++ ["#{signature_field}#{signature}"]

    new_data = Enum.join(dkim_header ++ headers ++ ["", body], "\r\n")

    mail = %Mail{mail | data: new_data}

    {:reply, {:ok, mail}, state}
  end

  defp chunkify(<<line::binary-size(64), rest::binary>>) do
    [" " <> line] ++ chunkify(rest)
  end

  defp chunkify(line) do
    [" " <> line]
  end
end
