defmodule Funnel.AllowList do
  import Ecto.Query

  @spec add(String.t()) :: :ok | {:error, any()}
  def add(email) do
    [user, domain] = String.split(email, "@", parts: 2)

    case user do
      "*" ->
        {:error, :wildcard_not_allowed}

      user ->
        entry = %Funnel.AllowList.Entry{
          user: user,
          domain: domain,
          created_at: DateTime.truncate(DateTime.utc_now(), :second)
        }

        with {:ok, _} <- Funnel.Repo.insert(entry, on_conflict: :nothing) do
          :ok
        end
    end
  end

  @spec contains?(String.t()) :: boolean()
  def contains?(email) do
    [user, domain] = String.split(email, "@", parts: 2)

    Funnel.AllowList.Entry
    |> where([p], (p.user == ^user or p.user == "*") and p.domain == ^domain)
    |> Funnel.Repo.exists?()
  end
end
