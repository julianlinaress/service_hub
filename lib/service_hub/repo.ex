defmodule ServiceHub.Repo do
  use Ecto.Repo,
    otp_app: :service_hub,
    adapter: Ecto.Adapters.Postgres
end
