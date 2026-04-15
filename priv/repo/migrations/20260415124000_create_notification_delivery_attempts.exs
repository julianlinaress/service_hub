defmodule ServiceHub.Repo.Migrations.CreateNotificationDeliveryAttempts do
  use Ecto.Migration

  def change do
    create table(:notification_delivery_attempts) do
      add :event_id,
          references(:notification_events,
            column: :id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :channel_id, references(:notification_channels, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :payload_snapshot, :map, null: false, default: %{}
      add :destination_snapshot, :map, null: false, default: %{}
      add :delivery_attempt_key, :string, null: false
      add :destination_ref, :string
      add :provider_message_id, :string
      add :provider_response_code, :string
      add :provider_response, :map
      add :error_code, :string
      add :error_message, :text
      add :attempt_count, :integer, null: false, default: 0
      add :oban_job_id, :bigint
      add :attempted_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_delivery_attempts, [:event_id])
    create index(:notification_delivery_attempts, [:channel_id])
    create index(:notification_delivery_attempts, [:status])
    create index(:notification_delivery_attempts, [:attempted_at])
    create unique_index(:notification_delivery_attempts, [:delivery_attempt_key])
  end
end
