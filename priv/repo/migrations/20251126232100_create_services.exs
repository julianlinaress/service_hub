defmodule ServiceHub.Repo.Migrations.CreateServices do
  use Ecto.Migration

  def change do
    create table(:services) do
      add :provider_id, references(:providers, type: :id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :owner, :string, null: false
      add :repo, :string, null: false
      add :default_ref, :string
      add :version_endpoint_template, :string
      add :healthcheck_endpoint_template, :string

      timestamps(type: :utc_datetime)
    end

    create index(:services, [:provider_id])
  end
end
