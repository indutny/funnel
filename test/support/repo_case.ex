defmodule Funnel.RepoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Funnel.Repo

      import Ecto
      import Ecto.Query
      import Funnel.RepoCase

      # and any other stuff
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Funnel.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Funnel.Repo, {:shared, self()})
    end

    :ok
  end
end
