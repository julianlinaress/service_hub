defmodule ServiceHub.Deployments.Deployment do
  @moduledoc """
  Deployment of a service on a specific host/environment.

  Health checks are mandatory and configurable per deployment; version checks are
  optional and can be toggled with per-deployment expectations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Services.Service

  schema "deployments" do
    field :name, :string
    field :host, :string
    field :env, :string
    field :api_key, :string
    field :current_version, :string
    field :last_version_checked_at, :utc_datetime
    field :last_health_status, :string, default: "unknown"
    field :last_health_checked_at, :utc_datetime
    field :version_check_enabled, :boolean, default: false
    field :version_expectation, :map, default: %{}
    field :healthcheck_expectation, :map, default: %{"allowed_statuses" => [200]}

    belongs_to :service, Service

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :service_id,
    :name,
    :host,
    :env,
    :healthcheck_expectation
  ]

  @cast_fields @required_fields ++
                 [
                   :api_key,
                   :current_version,
                   :last_version_checked_at,
                   :last_health_status,
                   :last_health_checked_at,
                   :version_check_enabled,
                   :version_expectation
                 ]

  @health_statuses ["unknown", "ok", "warning", "down"]

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_host()
    |> validate_inclusion(:last_health_status, @health_statuses)
    |> validate_expectation(:healthcheck_expectation)
    |> validate_expectation(:version_expectation)
    |> foreign_key_constraint(:service_id)
    |> unique_constraint(:name, name: :deployments_service_id_name_index)
    |> unique_constraint(:host, name: :deployments_service_id_host_index)
  end

  defp validate_host(changeset) do
    validate_change(changeset, :host, fn :host, value ->
      if String.contains?(value || "", [" ", "://"]) do
        [host: "must be a host without protocol or spaces"]
      else
        []
      end
    end)
  end

  defp validate_expectation(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_map(value) do
        []
      else
        [{field, "must be a map"}]
      end
    end)
  end
end
