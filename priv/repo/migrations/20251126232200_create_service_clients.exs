defmodule ServiceHub.Repo.Migrations.CreateServiceClients do
  use Ecto.Migration

  def change do
    create table(:service_clients) do
      add :service_id, references(:services, type: :id, on_delete: :delete_all), null: false
      add :client_id, references(:clients, type: :id, on_delete: :delete_all), null: false
      add :host, :string, null: false
      add :env, :string, null: false
      add :api_key, :string
      add :current_version, :string
      add :last_version_checked_at, :utc_datetime
      add :last_health_status, :string, null: false, default: "unknown"
      add :last_health_checked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:service_clients, [:service_id])
    create index(:service_clients, [:client_id])
  end
end
