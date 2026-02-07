defmodule ServiceHub.Repo.Migrations.CreateDeploymentNotificationStates do
  use Ecto.Migration

  def change do
    create table(:deployment_notification_states) do
      add :deployment_id, references(:deployments, on_delete: :delete_all), null: false
      add :check_type, :string, null: false
      add :last_status, :string
      add :last_version, :string
      add :last_notified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:deployment_notification_states, [:deployment_id, :check_type])
  end
end
