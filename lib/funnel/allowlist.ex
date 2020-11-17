defmodule Funnel.AllowList do
  import Ecto.Query

  @spec contains?(String.t()) :: boolean()
  def contains?(email) do
    [user, domain] = String.split(email, "@", parts: 2)

    Funnel.Repo.exists?(
      Funnel.AllowList.Entry
      |> where([p], (p.user == ^user or p.user == "*") and p.domain == ^domain))
  end
end
