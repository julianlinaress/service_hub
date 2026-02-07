defmodule ServiceHub.Repo.Migrations.CreateServiceNotificationRules do
  use Ecto.Migration

  def change do
    create table(:service_notification_rules) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :channel_id, references(:notification_channels, on_delete: :delete_all), null: false
      add :enabled, :boolean, default: true, null: false
      add :rules, :map, null: false, default: %{}
      add :notify_on_manual, :boolean, default: false, null: false
      add :mute_until, :utc_datetime_usec
      add :reminder_interval_minutes, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:service_notification_rules, [:service_id])
    create index(:service_notification_rules, [:channel_id])
    create unique_index(:service_notification_rules, [:service_id, :channel_id])
  end
end
