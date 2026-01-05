defmodule ServiceHub.Repo.Migrations.CreateAutomationTargets do
  use Ecto.Migration

  def change do
    create table(:automation_targets) do
      add :automation_id, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :bigint, null: false
      add :enabled, :boolean, default: true, null: false
      add :interval_minutes, :integer, null: false
      add :next_run_at, :utc_datetime_usec
      add :running_at, :utc_datetime_usec
      add :last_started_at, :utc_datetime_usec
      add :last_finished_at, :utc_datetime_usec
      add :paused_at, :utc_datetime_usec
      add :last_status, :string
      add :last_error, :text
      add :consecutive_failures, :integer, default: 0, null: false
      add :lock_version, :integer, default: 1, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:automation_targets, [:automation_id, :target_type, :target_id])
    create index(:automation_targets, [:next_run_at])
    create index(:automation_targets, [:automation_id, :enabled, :paused_at, :next_run_at])
  end
end
