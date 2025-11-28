defmodule ServiceHub.Repo.Migrations.AddProviderValidationFields do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :last_validation_status, :string, null: false, default: "unvalidated"
      add :last_validated_at, :utc_datetime
      add :last_validation_error, :text
    end

    create index(:providers, [:last_validation_status])
  end
end
