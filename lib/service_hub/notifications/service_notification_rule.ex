defmodule ServiceHub.Notifications.ServiceNotificationRule do
  @moduledoc """
  Configuration for which notifications to send for a service via a specific channel.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Services.Service

  schema "service_notification_rules" do
    field :enabled, :boolean, default: true
    field :rules, :map, default: %{}
    field :notify_on_manual, :boolean, default: false
    field :mute_until, :utc_datetime_usec
    field :reminder_interval_minutes, :integer

    belongs_to :service, Service
    belongs_to :channel, NotificationChannel

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:service_id, :channel_id]
  @cast_fields @required_fields ++
                 [:enabled, :rules, :notify_on_manual, :mute_until, :reminder_interval_minutes]

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:service_id, :channel_id])
  end

  @doc """
  Returns default notification rules for a service.
  """
  def default_rules do
    %{
      "health" => %{
        "warning" => true,
        "alert" => true,
        "recovery" => false
      },
      "version" => %{
        "change" => true,
        "error" => true
      },
      "automation" => %{
        "auto_paused" => true,
        "resumed" => false
      }
    }
  end
end
