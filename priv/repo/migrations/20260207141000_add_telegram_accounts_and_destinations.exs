defmodule ServiceHub.Repo.Migrations.AddTelegramAccountsAndDestinations do
  use Ecto.Migration

  def up do
    create table(:notification_telegram_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :bot_token, :text, null: false
      add :last_validated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_telegram_accounts, [:user_id, :bot_token])
    create index(:notification_telegram_accounts, [:user_id])

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
    create index(:notification_telegram_destinations, [:telegram_account_id])

    alter table(:notification_channels) do
      add :telegram_account_id,
          references(:notification_telegram_accounts, on_delete: :nilify_all)

      add :telegram_destination_id,
          references(:notification_telegram_destinations, on_delete: :nilify_all)
    end

    create index(:notification_channels, [:telegram_account_id])
    create index(:notification_channels, [:telegram_destination_id])

    execute(
      """
      INSERT INTO notification_telegram_accounts (user_id, name, bot_token, inserted_at, updated_at)
      SELECT DISTINCT
        user_id,
        'Migrated Telegram Bot',
        config->>'token',
        NOW(),
        NOW()
      FROM notification_channels
      WHERE provider = 'telegram'
        AND config ? 'token'
        AND NULLIF(config->>'token', '') IS NOT NULL
      ON CONFLICT (user_id, bot_token) DO NOTHING
      """,
      ""
    )

    execute(
      """
      INSERT INTO notification_telegram_destinations
        (telegram_account_id, chat_ref, inserted_at, updated_at)
      SELECT DISTINCT
        account.id,
        COALESCE(NULLIF(channel.config->>'chat_ref', ''), NULLIF(channel.config->>'chat_id', '')),
        NOW(),
        NOW()
      FROM notification_channels AS channel
      INNER JOIN notification_telegram_accounts AS account
        ON account.user_id = channel.user_id
       AND account.bot_token = channel.config->>'token'
      WHERE channel.provider = 'telegram'
        AND COALESCE(NULLIF(channel.config->>'chat_ref', ''), NULLIF(channel.config->>'chat_id', '')) IS NOT NULL
      ON CONFLICT (telegram_account_id, chat_ref) DO NOTHING
      """,
      ""
    )

    execute(
      """
      UPDATE notification_channels AS channel
      SET telegram_account_id = account.id,
          telegram_destination_id = destination.id,
          config =
            jsonb_strip_nulls(
              jsonb_build_object(
                'chat_ref', COALESCE(NULLIF(channel.config->>'chat_ref', ''), NULLIF(channel.config->>'chat_id', '')),
                'parse_mode', channel.config->>'parse_mode'
              )
            )
      FROM notification_telegram_accounts AS account,
           notification_telegram_destinations AS destination
      WHERE channel.provider = 'telegram'
        AND destination.telegram_account_id = account.id
        AND destination.chat_ref = COALESCE(NULLIF(channel.config->>'chat_ref', ''), NULLIF(channel.config->>'chat_id', ''))
        AND account.user_id = channel.user_id
        AND account.bot_token = channel.config->>'token'
      """,
      ""
    )
  end

  def down do
    alter table(:notification_channels) do
      remove :telegram_account_id
      remove :telegram_destination_id
    end

    drop table(:notification_telegram_destinations)
    drop table(:notification_telegram_accounts)
  end
end
