defmodule ServiceHub.Repo.Migrations.RelaxProviderAuthFk do
  use Ecto.Migration

  def change do
    drop constraint(:providers, "providers_auth_type_id_fkey")

    alter table(:providers) do
      modify :auth_type_id, references(:auth_types, type: :id, on_delete: :nilify_all), null: true
    end
  end
end
