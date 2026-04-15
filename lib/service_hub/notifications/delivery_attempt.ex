defmodule ServiceHub.Notifications.DeliveryAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Notifications.Event
  alias ServiceHub.Notifications.NotificationChannel

  schema "notification_delivery_attempts" do
    field :provider, :string
    field :status, :string, default: "pending"
    field :payload_snapshot, :map, default: %{}
    field :destination_snapshot, :map, default: %{}
    field :delivery_attempt_key, :string
    field :destination_ref, :string
    field :provider_message_id, :string
    field :provider_response_code, :string
    field :provider_response, :map
    field :error_code, :string
    field :error_message, :string
    field :attempt_count, :integer, default: 0
    field :oban_job_id, :integer
    field :attempted_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec

    belongs_to :event, Event, type: :string
    belongs_to :channel, NotificationChannel

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [
    :event_id,
    :channel_id,
    :provider,
    :status,
    :payload_snapshot,
    :destination_snapshot,
    :delivery_attempt_key
  ]

  @cast_fields @required_fields ++
                 [
                   :destination_ref,
                   :provider_message_id,
                   :provider_response_code,
                   :provider_response,
                   :error_code,
                   :error_message,
                   :attempt_count,
                   :oban_job_id,
                   :attempted_at,
                   :delivered_at,
                   :failed_at
                 ]

  @valid_statuses ["pending", "in_progress", "delivered", "failed"]

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:delivery_attempt_key)
  end
end
