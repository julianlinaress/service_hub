defmodule ServiceHub.Repo.Migrations.CreateDeployments do
  use Ecto.Migration

  def change do
    create table(:deployments) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :host, :string, null: false
      add :env, :string, null: false
      add :api_key, :string
      add :current_version, :string
      add :last_version_checked_at, :utc_datetime
      add :last_health_status, :string, null: false, default: "unknown"
      add :last_health_checked_at, :utc_datetime
      add :version_check_enabled, :boolean, default: false, null: false
      add :version_expectation, :map, default: %{}, null: false
      add :healthcheck_expectation, :map, default: %{"allowed_statuses" => [200]}, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:deployments, [:service_id])
    create unique_index(:deployments, [:service_id, :name])
    create unique_index(:deployments, [:service_id, :host])

    execute("""
    INSERT INTO deployments (
      service_id,
      name,
      host,
      env,
      api_key,
      current_version,
      last_version_checked_at,
      last_health_status,
      last_health_checked_at,
      inserted_at,
      updated_at
    )
    SELECT
      sc.service_id,
      trim(concat(c.name, ' ', sc.env)) as name,
      sc.host,
      sc.env,
      sc.api_key,
      sc.current_version,
      sc.last_version_checked_at,
      sc.last_health_status,
      sc.last_health_checked_at,
      now(),
      now()
    FROM service_clients sc
    JOIN clients c ON c.id = sc.client_id
    """)
  end
end
