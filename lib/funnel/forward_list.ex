defmodule Funnel.ForwardList do
  import Ecto.Query

  @spec map(FunnelSMTP.forward_path()) :: FunnelSMTP.forward_path()
  def map(:postmaster) do
    {:ok, :postmaster}
  end

  def map(email) do
    maybe_entry =
      ForwardList.Entry
      |> where([p], p.from == ^email)
      |> select([p], p.to)
      |> Funnel.Repo.one()

    case maybe_entry do
      nil -> {:error, :not_found}
      entry -> {:ok, entry.to}
    end
  end
end
