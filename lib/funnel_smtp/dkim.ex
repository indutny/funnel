defmodule FunnelSMTP.DKIM do
  @moduledoc """
  DKIM Signatures.
  """

  use GenServer
  use TypedStruct

  alias FunnelSMTP.Mail

  typedstruct module: Config do
    field :private_key, :public_key.private_key(), enforce: true
  end

  @type t :: GenServer.server()
  @type options :: [GenServer.options() | {:private_key, String.t()}]

  # Public API

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{
      private_key: Keyword.fetch!(opts, :private_key)
    }, opts)
  end

  @spec sign(t(), Mail.t()) :: String.t()
  def sign(server, mail) do
    {:ok, _signature} = GenServer.call(server, {:sign, "hello"})
    mail
  end

  # GenServer implementation

  @impl true
  def init(%{ private_key: private_key }) do
    pem = File.read!(private_key)
    [entry] = :public_key.pem_decode(pem)
    private_key = :public_key.pem_entry_decode(entry)

    {:ok, %Config{private_key: private_key}}
  end

  @impl true
  def handle_call({:sign, message}, _from, state) do
    %{private_key: private_key} = state

    signature = :public_key.sign(message, :sha256, private_key)

    {:reply, {:ok, signature}, state}
  end
end
