defmodule ServiceHub.Repo.Migrations.CreateAutomationRuns do
  use Ecto.Migration

  def change do
    create table(:automation_runs) do
      add :automation_id, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :bigint, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :duration_ms, :integer
      add :summary, :text
      add :error, :text
      add :attempt, :integer, null: false
      add :node, :string

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime)
    end

    create index(:automation_runs, [:automation_id, :target_type, :target_id, :inserted_at])
    create index(:automation_runs, [:inserted_at])
  end
end
