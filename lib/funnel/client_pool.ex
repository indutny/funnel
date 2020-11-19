defmodule Funnel.ClientPool do
  use Task, restart: :permanent

  alias Funnel.Client

  @spec start_link([Registry.start_option()]) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    Registry.start_link([keys: :unique] ++ opts)
  end

  @spec get(Registry.registry(), String.t()) :: pid()
  def get(registry, domain) do
    case Registry.lookup(registry, domain) do
      [{client, _}] ->
        client

      _ ->
        name = {:via, Registry, {registry, domain}}

        # TODO(indutny): supply port
        {:ok, pid} =
          Client.start(
            %Client.Config{host: domain},
            name: name
          )

        pid
    end
  end
end
