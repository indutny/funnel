defmodule Funnel.Repo do
  use Ecto.Repo,
    otp_app: :funnel,
    adapter: Ecto.Adapters.Postgres
end
