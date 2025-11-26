defmodule ServiceHub.Repo.Migrations.CreateAuthTypes do
  use Ecto.Migration

  def change do
    create table(:auth_types) do
      add :name, :string, null: false
      add :key, :string, null: false
      add :required_fields, :map, null: false, default: %{}
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:auth_types, [:user_id, :key])
    create index(:auth_types, [:user_id])
  end
end
