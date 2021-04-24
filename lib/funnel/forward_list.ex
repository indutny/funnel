defmodule Funnel.ForwardList do
  import Ecto.Query

  @spec map(FunnelSMTP.forward_path()) ::
          {:ok, FunnelSMTP.forward_path()} | {:error, :not_found}
  def map(:postmaster) do
    {:ok, :postmaster}
  end

  def map(email) do
    maybe_entry =
      Funnel.ForwardList.Entry
      |> where([p], p.source == ^email)
      |> select([p], p.target)
      |> Funnel.Repo.one()

    case maybe_entry do
      nil -> {:error, :not_found}
      target -> {:ok, target}
    end
  end
end
