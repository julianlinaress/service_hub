defmodule ServiceHub.Repo.Migrations.CreateNotificationChannels do
  use Ecto.Migration

  def change do
    create table(:notification_channels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :name, :string, null: false
      add :config, :map, null: false, default: %{}
      add :enabled, :boolean, default: true, null: false
      add :last_error, :text
      add :last_sent_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_channels, [:user_id])
    create index(:notification_channels, [:enabled])
  end
end
