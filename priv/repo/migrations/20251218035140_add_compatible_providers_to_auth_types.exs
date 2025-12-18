defmodule ServiceHub.Repo.Migrations.AddCompatibleProvidersToAuthTypes do
  use Ecto.Migration

  def change do
    alter table(:auth_types) do
      add :compatible_providers, {:array, :string}, default: []
    end
  end
end
