defmodule ServiceHub.Notifications.Channels do
  @moduledoc false
  import Ecto.Query, warn: false
  import ServiceHub.Notifications.Helpers

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.Events
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.TelegramAccounts
  alias ServiceHub.Repo
  alias ServiceHub.Workers.NotificationWorker

  def list_channels(%Scope{} = scope) do
    NotificationChannel
    |> where([c], c.user_id == ^scope.user.id)
    |> order_by([c], asc: c.name)
    |> preload([:telegram_account, :telegram_destination])
    |> Repo.all()
  end

  def get_channel!(%Scope{} = scope, id) do
    NotificationChannel
    |> where([c], c.id == ^id and c.user_id == ^scope.user.id)
    |> preload([:telegram_account, :telegram_destination])
    |> Repo.one!()
  end

  def create_channel(%Scope{} = scope, attrs) do
    attrs = normalize_channel_attrs(scope, attrs)

    %NotificationChannel{user_id: scope.user.id}
    |> NotificationChannel.changeset(attrs)
    |> Repo.insert()
  end

  def update_channel(%Scope{} = scope, %NotificationChannel{} = channel, attrs) do
    true = channel.user_id == scope.user.id

    attrs = normalize_channel_attrs(scope, attrs)

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
      "tags" => %{
        "source" => "manual"
      }
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

  defp normalize_channel_attrs(%Scope{} = scope, attrs) do
    provider = get_value(attrs, "provider")

    if provider == "telegram" do
      maybe_attach_telegram_refs(scope, attrs)
    else
      attrs
    end
  end

  defp maybe_attach_telegram_refs(%Scope{} = scope, attrs) do
    account_id = get_value(attrs, "telegram_account_id")
    destination_id = get_value(attrs, "telegram_destination_id")

    if present?(account_id) and present?(destination_id) do
      attrs
    else
      maybe_attach_telegram_refs_from_config(scope, attrs)
    end
  end

  defp maybe_attach_telegram_refs_from_config(%Scope{} = scope, attrs) do
    config = get_value(attrs, "config") || %{}
    token = get_value(config, "token")
    chat_ref = get_value(config, "chat_ref") || get_value(config, "chat_id")

    if present?(token) and present?(chat_ref) do
      account = TelegramAccounts.find_or_create_telegram_account(scope.user.id, token)
      destination = TelegramAccounts.find_or_create_telegram_destination(account.id, chat_ref)

      attrs
      |> put_value("telegram_account_id", account.id)
      |> put_value("telegram_destination_id", destination.id)
      |> put_value("config", build_telegram_channel_config(config, chat_ref))
    else
      attrs
    end
  end

  defp build_telegram_channel_config(config, chat_ref) do
    parse_mode = get_value(config, "parse_mode") || "HTML"
    %{"chat_ref" => chat_ref, "parse_mode" => parse_mode}
  end
end
