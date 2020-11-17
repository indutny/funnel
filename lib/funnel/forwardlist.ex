defmodule Funnel.ForwardList do
  import Ecto.Query

  @spec contains?(String.t()) :: boolean()
  def contains?(email) do
    Funnel.ForwardList.Entry
    |> where([p], p.from == ^email)
    |> Funnel.Repo.exists?()
  end
end
