defmodule ServiceHub.Repo.Migrations.MakeTypesGlobal do
  use Ecto.Migration

  def change do
    drop index(:provider_types, [:user_id, :key])
    drop index(:provider_types, [:user_id])

    alter table(:provider_types) do
      remove :user_id
    end

    create unique_index(:provider_types, [:key])

    drop index(:auth_types, [:user_id, :key])
    drop index(:auth_types, [:user_id])

    alter table(:auth_types) do
      remove :user_id
    end

    create unique_index(:auth_types, [:key])
  end
end
