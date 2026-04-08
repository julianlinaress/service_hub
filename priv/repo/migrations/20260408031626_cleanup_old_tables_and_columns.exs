defmodule ServiceHub.Repo.Migrations.CleanupOldTablesAndColumns do
  use Ecto.Migration

  def up do
    # Drop audit_logs table — created but never used (no Ecto schema)
    drop_if_exists table(:audit_logs)

    # Remove lock_version column from automation_targets — was used by the old
    # GenServer scheduler's optimistic locking, replaced by Oban's job locking
    alter table(:automation_targets) do
      remove :lock_version
    end

    # Delete the dummy retention_cleaner automation target — the retention
    # cleaner now runs as an Oban cron job, no longer needs a target record
    execute """
    DELETE FROM automation_runs WHERE automation_id = 'retention_cleaner';
    """

    execute """
    DELETE FROM automation_targets WHERE automation_id = 'retention_cleaner';
    """
  end

  def down do
    create table(:audit_logs) do
      add :user_id, references(:users, type: :id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :bigint, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:entity_type, :entity_id])

    alter table(:automation_targets) do
      add :lock_version, :integer, default: 1
    end

    # Re-insert the retention_cleaner dummy target
    execute """
    INSERT INTO automation_targets (
      automation_id, target_type, target_id, enabled, interval_minutes,
      next_run_at, consecutive_failures, lock_version, inserted_at, updated_at
    ) VALUES (
      'retention_cleaner', 'system', 1, true, 60,
      now(), 0, 1, now(), now()
    )
    ON CONFLICT (automation_id, target_type, target_id) DO NOTHING;
    """
  end
end
