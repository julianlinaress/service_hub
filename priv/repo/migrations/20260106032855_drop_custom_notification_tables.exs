defmodule ServiceHub.Repo.Migrations.DropCustomNotificationTables do
  use Ecto.Migration

  def change do
    # Drop deprecated notification tables replaced by unified event persistence
    drop_if_exists table(:notification_deliveries)
    drop_if_exists table(:notification_outbox)
    drop_if_exists table(:notification_states)
  end
end
