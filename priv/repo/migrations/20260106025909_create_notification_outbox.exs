defmodule ServiceHub.Repo.Migrations.CreateNotificationOutbox do
  use Ecto.Migration

  def change do
    create table(:notification_outbox) do
      add :channel_id, references(:notification_channels, on_delete: :delete_all), null: false
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :deployment_id, references(:deployments, on_delete: :delete_all)
      add :check_type, :string, null: false
      add :severity, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :attempt, :integer, default: 0, null: false
      add :next_run_at, :utc_datetime_usec
      add :locked_at, :utc_datetime_usec
      add :lock_owner, :string
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_outbox, [:channel_id])
    create index(:notification_outbox, [:service_id])
    create index(:notification_outbox, [:deployment_id])
    create index(:notification_outbox, [:status])
    create index(:notification_outbox, [:next_run_at])
    create index(:notification_outbox, [:locked_at])
  end
end
