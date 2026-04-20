defmodule ServiceHub.Notifications.Channels do
  @moduledoc false
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.Events
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Repo
  alias ServiceHub.Workers.NotificationWorker

  def list_channels(%Scope{} = scope) do
    NotificationChannel
    |> where([c], c.user_id == ^scope.user.id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  def get_channel!(%Scope{} = scope, id) do
    NotificationChannel
    |> where([c], c.id == ^id and c.user_id == ^scope.user.id)
    |> Repo.one!()
  end

  def create_channel(%Scope{} = scope, attrs) do
    %NotificationChannel{user_id: scope.user.id}
    |> NotificationChannel.changeset(attrs)
    |> Repo.insert()
  end

  def update_channel(%Scope{} = scope, %NotificationChannel{} = channel, attrs) do
    true = channel.user_id == scope.user.id

    channel
    |> NotificationChannel.changeset(attrs)
    |> Repo.update()
  end

  def delete_channel(%Scope{} = scope, %NotificationChannel{} = channel) do
    true = channel.user_id == scope.user.id
    Repo.delete(channel)
  end

  def change_channel(%Scope{} = _scope, %NotificationChannel{} = channel, attrs \\ %{}) do
    NotificationChannel.changeset(channel, attrs)
  end

  def enqueue_channel_test_notification(%Scope{} = scope, %NotificationChannel{} = channel) do
    true = channel.user_id == scope.user.id

    event_id = Ecto.UUID.generate()

    event = %{
      "id" => event_id,
      "name" => "health.info",
      "payload" => %{
        "service_id" => 0,
        "deployment_id" => 0,
        "check_type" => "test",
        "message" => "Test notification from ServiceHub",
        "metadata" => %{
          "status" => "test",
          "host" => "test.example.com",
          "env" => "test"
        }
      },
      "tags" => %{"source" => "manual"}
    }

    Events.emit(event["name"], event["payload"],
      id: event_id,
      tags: event["tags"],
      actor: "notification_channel_test"
    )

    %{event: event, channel_id: channel.id}
    |> NotificationWorker.new(max_attempts: 1)
    |> Oban.insert()
  end
end
