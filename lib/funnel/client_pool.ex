defmodule Funnel.ClientPool do
  use Task, restart: :permanent

  @spec start_link([Registry.start_option()]) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    Registry.start_link([keys: :unique] ++ opts)
  end

  @spec get(Registry.registry(), String.t()) :: pid()
  def get(registry, domain) do
    case Registry.lookup(registry, domain) do
      [client] ->
        client
      _ ->
        name = {:via, Registry, {registry, domain}}

        {:ok, pid} = Funnel.Client.start_link(%Funnel.Client.Config{
          remote_domain: domain,
        }, name: name)

        pid
    end
  end
end
