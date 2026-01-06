defmodule ServiceHub.Repo.Migrations.CreateNotificationStates do
  use Ecto.Migration

  def change do
    create table(:notification_states) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :deployment_id, references(:deployments, on_delete: :delete_all)
      add :check_type, :string, null: false
      add :last_status, :string
      add :last_version, :string
      add :last_notified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_states, [:service_id])
    create index(:notification_states, [:deployment_id])
    create unique_index(:notification_states, [:service_id, :deployment_id, :check_type])
  end
end
