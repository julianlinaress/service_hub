defmodule ServiceHub.Notifications do
  @moduledoc """
  Notification management system.

  Handles notification channels and service notification rules.
  Uses internal event emission and delivery.
  """

  alias ServiceHub.Notifications.Channels
  alias ServiceHub.Notifications.Rules
  alias ServiceHub.Notifications.TelegramAccounts

  # Channel Management

  defdelegate list_channels(scope), to: Channels
  defdelegate get_channel!(scope, id), to: Channels
  defdelegate create_channel(scope, attrs), to: Channels
  defdelegate update_channel(scope, channel, attrs), to: Channels
  defdelegate delete_channel(scope, channel), to: Channels
  defdelegate change_channel(scope, channel, attrs \\ %{}), to: Channels
  defdelegate enqueue_channel_test_notification(scope, channel), to: Channels

  # Telegram Accounts & Destinations

  defdelegate list_telegram_accounts(scope), to: TelegramAccounts
  defdelegate list_telegram_destinations(scope, account_id), to: TelegramAccounts
  defdelegate discover_telegram_destinations(scope, channel_attrs), to: TelegramAccounts

  # Service Notification Rules

  defdelegate list_service_rules(scope, service_id), to: Rules
  defdelegate get_service_rule!(scope, id), to: Rules
  defdelegate create_service_rule(scope, attrs), to: Rules
  defdelegate update_service_rule(scope, rule, attrs), to: Rules
  defdelegate delete_service_rule(scope, rule), to: Rules
  defdelegate change_service_rule(scope, rule, attrs \\ %{}), to: Rules
end
