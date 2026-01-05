defmodule ServiceHub.Automations.AutomationTarget do
  @moduledoc """
  Schema for automation_targets table.
  Tracks scheduling state and execution history for automation tasks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "automation_targets" do
    field :automation_id, :string
    field :target_type, :string
    field :target_id, :integer
    field :enabled, :boolean, default: true
    field :interval_minutes, :integer
    field :next_run_at, :utc_datetime_usec
    field :running_at, :utc_datetime_usec
    field :last_started_at, :utc_datetime_usec
    field :last_finished_at, :utc_datetime_usec
    field :paused_at, :utc_datetime_usec
    field :last_status, :string
    field :last_error, :string
    field :consecutive_failures, :integer, default: 0
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @required_fields [:automation_id, :target_type, :target_id, :enabled, :interval_minutes]
  @optional_fields [
    :next_run_at,
    :running_at,
    :last_started_at,
    :last_finished_at,
    :paused_at,
    :last_status,
    :last_error,
    :consecutive_failures,
    :lock_version
  ]

  @doc false
  def changeset(target, attrs) do
    target
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:last_status, ["ok", "warning", "error", "timeout", "stale"])
    |> unique_constraint([:automation_id, :target_type, :target_id])
  end
end
