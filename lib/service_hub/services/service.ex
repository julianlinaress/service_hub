defmodule ServiceHub.Services.Service do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Providers.Provider

  schema "services" do
    field :name, :string
    field :owner, :string
    field :repo, :string
    field :default_ref, :string
    field :repo_full_name, :string, virtual: true
    field :version_endpoint_template, :string
    field :healthcheck_endpoint_template, :string
    belongs_to :provider, Provider

    timestamps(type: :utc_datetime)
  end

  def changeset(service, attrs) do
    service
    |> cast(attrs, [
      :name,
      :owner,
      :repo,
      :default_ref,
      :repo_full_name,
      :version_endpoint_template,
      :healthcheck_endpoint_template,
      :provider_id
    ])
    |> validate_required([:name, :owner, :repo, :provider_id])
    |> assoc_constraint(:provider)
  end
end
