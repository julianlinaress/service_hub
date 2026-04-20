defmodule ServiceHub.Notifications do
  @moduledoc """
  Notification management system.

  Handles notification channels and service notification rules.
  Uses internal event emission and delivery.
  """

  alias ServiceHub.Notifications.Channels
  alias ServiceHub.Notifications.Rules
  alias ServiceHub.Notifications.TelegramConnections

  # Channel Management

  defdelegate list_channels(scope), to: Channels
  defdelegate get_channel!(scope, id), to: Channels
  defdelegate create_channel(scope, attrs), to: Channels
  defdelegate update_channel(scope, channel, attrs), to: Channels
  defdelegate delete_channel(scope, channel), to: Channels
  defdelegate change_channel(scope, channel, attrs \\ %{}), to: Channels
  defdelegate enqueue_channel_test_notification(scope, channel), to: Channels

  # Telegram Connection

  defdelegate get_telegram_connection(scope), to: TelegramConnections, as: :get_connection

  defdelegate upsert_telegram_connection(scope, attrs),
    to: TelegramConnections,
    as: :upsert_connection

  defdelegate delete_telegram_connection(scope), to: TelegramConnections, as: :delete_connection

  defdelegate verify_telegram_widget_payload(params),
    to: TelegramConnections,
    as: :verify_widget_payload

  # Service Notification Rules

  defdelegate list_service_rules(scope, service_id), to: Rules
  defdelegate get_service_rule!(scope, id), to: Rules
  defdelegate create_service_rule(scope, attrs), to: Rules
  defdelegate update_service_rule(scope, rule, attrs), to: Rules
  defdelegate delete_service_rule(scope, rule), to: Rules
  defdelegate change_service_rule(scope, rule, attrs \\ %{}), to: Rules
end
