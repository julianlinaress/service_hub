defmodule ServiceHub.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :base_url, :string, null: false
      add :auth_type, :string, null: false
      add :auth_data, :map, null: false, default: %{}
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:providers, [:user_id])
  end
end
