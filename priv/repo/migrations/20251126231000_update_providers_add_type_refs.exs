defmodule ServiceHub.Repo.Migrations.UpdateProvidersAddTypeRefs do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :provider_type_id, references(:provider_types, type: :id, on_delete: :restrict),
        null: false

      add :auth_type_id, references(:auth_types, type: :id, on_delete: :restrict), null: false
      remove :type
      remove :auth_type
    end

    create index(:providers, [:provider_type_id])
    create index(:providers, [:auth_type_id])
  end
end
