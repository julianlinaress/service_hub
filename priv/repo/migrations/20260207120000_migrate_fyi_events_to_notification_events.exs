defmodule ServiceHub.Repo.Migrations.MigrateFyiEventsToNotificationEvents do
  use Ecto.Migration

  def up do
    create table(:notification_events, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :payload, :map, default: %{}
      add :tags, :map, default: %{}
      add :actor, :string
      add :source, :string

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:notification_events, [:name])
    create index(:notification_events, [:actor])
    create index(:notification_events, [:inserted_at])

    execute(
      """
      DO $$
      BEGIN
        IF to_regclass('public.fyi_events') IS NOT NULL THEN
          INSERT INTO notification_events (id, name, payload, tags, actor, source, inserted_at)
          SELECT id, name, payload, tags, actor, source, inserted_at
          FROM fyi_events
          ON CONFLICT (id) DO NOTHING;
        END IF;
      END $$;
      """,
      ""
    )

    drop_if_exists table(:fyi_events)
  end

  def down do
    create table(:fyi_events, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :payload, :map, default: %{}
      add :tags, :map, default: %{}
      add :actor, :string
      add :source, :string

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:fyi_events, [:name])
    create index(:fyi_events, [:actor])
    create index(:fyi_events, [:inserted_at])

    execute(
      """
      DO $$
      BEGIN
        IF to_regclass('public.notification_events') IS NOT NULL THEN
          INSERT INTO fyi_events (id, name, payload, tags, actor, source, inserted_at)
          SELECT id, name, payload, tags, actor, source, inserted_at
          FROM notification_events
          ON CONFLICT (id) DO NOTHING;
        END IF;
      END $$;
      """,
      ""
    )

    drop_if_exists table(:notification_events)
  end
end
