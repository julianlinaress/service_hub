defmodule ServiceHub.Automations.AutomationRun do
  @moduledoc """
  Schema for automation_runs table.
  Audit log of automation executions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "automation_runs" do
    field :automation_id, :string
    field :target_type, :string
    field :target_id, :integer
    field :status, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :summary, :string
    field :error, :string
    field :attempt, :integer
    field :node, :string

    timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime)
  end

  @required_fields [:automation_id, :target_type, :target_id, :status, :started_at, :attempt]
  @optional_fields [:finished_at, :duration_ms, :summary, :error, :node]

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["ok", "warning", "error", "timeout", "stale"])
  end
end
