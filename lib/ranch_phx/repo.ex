defmodule RanchPhx.Repo do
  use Ecto.Repo,
    otp_app: :ranch_phx,
    adapter: Ecto.Adapters.Postgres
end
