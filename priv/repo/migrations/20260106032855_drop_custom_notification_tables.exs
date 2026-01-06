defmodule ServiceHub.Repo.Migrations.DropCustomNotificationTables do
  use Ecto.Migration

  def change do
    # Drop custom notification tables - FYI handles event persistence
    drop_if_exists table(:notification_deliveries)
    drop_if_exists table(:notification_outbox)
    drop_if_exists table(:notification_states)
  end
end
