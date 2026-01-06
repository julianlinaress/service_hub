defmodule ServiceHub.Repo.Migrations.CreateNotificationDeliveries do
  use Ecto.Migration

  def change do
    create table(:notification_deliveries) do
      add :channel_id, references(:notification_channels, on_delete: :delete_all), null: false
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :deployment_id, references(:deployments, on_delete: :delete_all)
      add :check_type, :string, null: false
      add :severity, :string, null: false
      add :status, :string, null: false
      add :dedupe_key, :string, null: false
      add :sent_at, :utc_datetime_usec
      add :error, :text
      add :response, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_deliveries, [:channel_id])
    create index(:notification_deliveries, [:service_id])
    create index(:notification_deliveries, [:deployment_id])
    create index(:notification_deliveries, [:sent_at])
    create unique_index(:notification_deliveries, [:dedupe_key])
  end
end
