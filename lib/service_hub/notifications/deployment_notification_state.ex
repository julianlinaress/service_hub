defmodule ServiceHub.Notifications.DeploymentNotificationState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deployment_notification_states" do
    field :check_type, :string
    field :last_status, :string
    field :last_version, :string
    field :last_notified_at, :utc_datetime_usec

    belongs_to :deployment, ServiceHub.Deployments.Deployment

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:deployment_id, :check_type, :last_status, :last_version, :last_notified_at])
    |> validate_required([:deployment_id, :check_type])
    |> unique_constraint([:deployment_id, :check_type])
  end
end
