defmodule ServiceHub.Repo.Migrations.CreateAccountConnections do
  use Ecto.Migration

  def change do
    create table(:account_connections) do
      add :provider_key, :string, null: false
      add :token, :text, null: false
      add :refresh_token, :text
      add :scope, :string
      add :expires_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:account_connections, [:user_id])
    create unique_index(:account_connections, [:user_id, :provider_key])
  end
end
