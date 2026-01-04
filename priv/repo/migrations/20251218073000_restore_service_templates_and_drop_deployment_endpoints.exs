defmodule ServiceHub.Repo.Migrations.RestoreServiceTemplatesAndDropDeploymentEndpoints do
  use Ecto.Migration

  def up do
    alter table(:services) do
      add :version_endpoint_template, :string
      add :healthcheck_endpoint_template, :string
    end

    alter table(:deployments) do
      remove :health_endpoint
      remove :version_endpoint
    end
  end

  def down do
    alter table(:deployments) do
      add :health_endpoint, :string, null: false, default: "https://{{host}}/api/health"
      add :version_endpoint, :string, default: "https://{{host}}/api/version"
    end

    alter table(:services) do
      remove :version_endpoint_template
      remove :healthcheck_endpoint_template
    end
  end
end
