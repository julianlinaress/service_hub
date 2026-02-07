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
    field :automatic_checks_enabled, :boolean, default: false
    field :check_interval_minutes, :integer

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
                   :version_expectation,
                   :automatic_checks_enabled,
                   :check_interval_minutes
                 ]

  @health_statuses ["unknown", "ok", "warning", "down"]
  @allowed_intervals [1, 2, 5, 10, 30, 60, 120, 360, 720, 1440]

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_host()
    |> validate_inclusion(:last_health_status, @health_statuses)
    |> validate_expectation(:healthcheck_expectation)
    |> validate_expectation(:version_expectation)
    |> validate_automatic_checks()
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

  defp validate_automatic_checks(changeset) do
    automatic_enabled = get_field(changeset, :automatic_checks_enabled)
    interval = get_field(changeset, :check_interval_minutes)

    cond do
      automatic_enabled and is_nil(interval) ->
        add_error(
          changeset,
          :check_interval_minutes,
          "must be set when automatic checks are enabled"
        )

      automatic_enabled and interval not in @allowed_intervals ->
        add_error(changeset, :check_interval_minutes, "must be one of the allowed intervals")

      not automatic_enabled ->
        changeset

      true ->
        changeset
    end
  end
end
