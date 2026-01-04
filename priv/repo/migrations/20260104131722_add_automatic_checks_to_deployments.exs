defmodule ServiceHub.Repo.Migrations.AddAutomaticChecksToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :automatic_checks_enabled, :boolean, default: false, null: false
      add :check_interval_minutes, :integer
    end
  end
end
