defmodule ServiceHub.Repo.Migrations.RefactorTelegramToConnectionModel do
  use Ecto.Migration

  def up do
    alter table(:notification_channels) do
      remove :telegram_account_id
      remove :telegram_destination_id
    end

    drop_if_exists table(:notification_telegram_destinations)
    drop_if_exists table(:notification_telegram_accounts)

    create table(:user_telegram_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :telegram_id, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string
      add :username, :string
      add :connected_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_telegram_connections, [:user_id])
    create index(:user_telegram_connections, [:telegram_id])
  end

  def down do
    drop table(:user_telegram_connections)

    create table(:notification_telegram_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :bot_token, :text, null: false
      add :last_validated_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_telegram_accounts, [:user_id, :bot_token])

    create table(:notification_telegram_destinations) do
      add :telegram_account_id,
          references(:notification_telegram_accounts, on_delete: :delete_all),
          null: false

      add :chat_ref, :string, null: false
      add :chat_type, :string
      add :title, :string
      add :username, :string
      add :message_thread_id, :bigint
      add :verified_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_telegram_destinations, [:telegram_account_id, :chat_ref])

    alter table(:notification_channels) do
      add :telegram_account_id,
          references(:notification_telegram_accounts, on_delete: :nilify_all)

      add :telegram_destination_id,
          references(:notification_telegram_destinations, on_delete: :nilify_all)
    end
  end
end
