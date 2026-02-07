defmodule ServiceHub.Notifications do
  @moduledoc """
  Notification management system.

  Handles notification channels and service notification rules.
  Uses internal event emission and delivery.
  """
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.ServiceNotificationRule
  alias ServiceHub.Notifications.TelegramAccount
  alias ServiceHub.Notifications.TelegramDestination
  alias ServiceHub.Repo
  alias ServiceHub.Services.Service

  # Channel Management

  @doc """
  Lists all notification channels for the current user.
  """
  def list_channels(%Scope{} = scope) do
    NotificationChannel
    |> where([c], c.user_id == ^scope.user.id)
    |> order_by([c], asc: c.name)
    |> preload([:telegram_account, :telegram_destination])
    |> Repo.all()
  end

  @doc """
  Gets a single notification channel by ID for the current user.
  """
  def get_channel!(%Scope{} = scope, id) do
    NotificationChannel
    |> where([c], c.id == ^id and c.user_id == ^scope.user.id)
    |> preload([:telegram_account, :telegram_destination])
    |> Repo.one!()
  end

  @doc """
  Creates a new notification channel.
  """
  def create_channel(%Scope{} = scope, attrs) do
    attrs = normalize_channel_attrs(scope, attrs)

    %NotificationChannel{user_id: scope.user.id}
    |> NotificationChannel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification channel.
  """
  def update_channel(%Scope{} = scope, %NotificationChannel{} = channel, attrs) do
    true = channel.user_id == scope.user.id

    attrs = normalize_channel_attrs(scope, attrs)

    channel
    |> NotificationChannel.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification channel.
  """
  def delete_channel(%Scope{} = scope, %NotificationChannel{} = channel) do
    true = channel.user_id == scope.user.id
    Repo.delete(channel)
  end

  @doc """
  Returns a changeset for tracking channel changes.
  """
  def change_channel(%Scope{} = _scope, %NotificationChannel{} = channel, attrs \\ %{}) do
    NotificationChannel.changeset(channel, attrs)
  end

  # Service Notification Rules

  @doc """
  Lists notification rules for a service.
  """
  def list_service_rules(%Scope{} = scope, service_id) do
    ServiceNotificationRule
    |> join(:inner, [r], s in assoc(r, :service))
    |> join(:inner, [_r, s], p in assoc(s, :provider))
    |> join(:inner, [r], c in assoc(r, :channel))
    |> where([_r, _s, p, c], p.user_id == ^scope.user.id and c.user_id == ^scope.user.id)
    |> where([r], r.service_id == ^service_id)
    |> preload([r, _s, _p, c], [:service, :channel])
    |> Repo.all()
  end

  @doc """
  Gets a service notification rule.
  """
  def get_service_rule!(%Scope{} = scope, id) do
    ServiceNotificationRule
    |> join(:inner, [r], s in assoc(r, :service))
    |> join(:inner, [_r, s], p in assoc(s, :provider))
    |> join(:inner, [r], c in assoc(r, :channel))
    |> where(
      [r, _s, p, c],
      r.id == ^id and p.user_id == ^scope.user.id and c.user_id == ^scope.user.id
    )
    |> preload([r, _s, _p, c], [:service, :channel])
    |> Repo.one!()
  end

  @doc """
  Creates a notification rule for a service.
  """
  def create_service_rule(%Scope{} = scope, attrs) do
    with {:ok, _service} <- verify_service_access(scope, attrs["service_id"]),
         {:ok, _channel} <- verify_channel_access(scope, attrs["channel_id"]) do
      %ServiceNotificationRule{}
      |> ServiceNotificationRule.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a service notification rule.
  """
  def update_service_rule(%Scope{} = scope, %ServiceNotificationRule{} = rule, attrs) do
    rule = Repo.preload(rule, [:service, :channel])

    with {:ok, _service} <- verify_service_access(scope, rule.service_id),
         {:ok, _channel} <- verify_channel_access(scope, rule.channel_id) do
      rule
      |> ServiceNotificationRule.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a service notification rule.
  """
  def delete_service_rule(%Scope{} = scope, %ServiceNotificationRule{} = rule) do
    rule = Repo.preload(rule, [:service, :channel])

    with {:ok, _service} <- verify_service_access(scope, rule.service_id),
         {:ok, _channel} <- verify_channel_access(scope, rule.channel_id) do
      Repo.delete(rule)
    end
  end

  @doc """
  Returns a changeset for tracking rule changes.
  """
  def change_service_rule(%Scope{} = _scope, %ServiceNotificationRule{} = rule, attrs \\ %{}) do
    ServiceNotificationRule.changeset(rule, attrs)
  end

  # Private Helpers

  defp verify_service_access(%Scope{} = scope, service_id) when is_integer(service_id) do
    case Repo.one(
           from s in Service,
             join: p in assoc(s, :provider),
             where: s.id == ^service_id and p.user_id == ^scope.user.id,
             select: s
         ) do
      nil -> {:error, :not_found}
      service -> {:ok, service}
    end
  end

  defp verify_service_access(_scope, _), do: {:error, :invalid_service_id}

  defp verify_channel_access(%Scope{} = scope, channel_id) when is_integer(channel_id) do
    case Repo.one(
           from c in NotificationChannel,
             where: c.id == ^channel_id and c.user_id == ^scope.user.id,
             select: c
         ) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end

  defp verify_channel_access(_scope, _), do: {:error, :invalid_channel_id}

  defp normalize_channel_attrs(%Scope{} = scope, attrs) do
    provider = get_value(attrs, "provider")

    if provider == "telegram" do
      maybe_attach_telegram_refs(scope, attrs)
    else
      attrs
    end
  end

  defp maybe_attach_telegram_refs(%Scope{} = scope, attrs) do
    config = get_value(attrs, "config") || %{}
    token = get_value(config, "token")
    chat_ref = get_value(config, "chat_ref") || get_value(config, "chat_id")

    if present?(token) and present?(chat_ref) do
      account = find_or_create_telegram_account(scope.user.id, token)
      destination = find_or_create_telegram_destination(account.id, chat_ref)

      attrs
      |> put_value("telegram_account_id", account.id)
      |> put_value("telegram_destination_id", destination.id)
      |> put_value("config", build_telegram_channel_config(config, chat_ref))
    else
      attrs
    end
  end

  defp find_or_create_telegram_account(user_id, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      user_id: user_id,
      name: "Telegram Bot",
      bot_token: token,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      TelegramAccount,
      [attrs],
      on_conflict: [set: [updated_at: now]],
      conflict_target: [:user_id, :bot_token]
    )

    Repo.get_by!(TelegramAccount, user_id: user_id, bot_token: token)
  end

  defp find_or_create_telegram_destination(account_id, chat_ref) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      telegram_account_id: account_id,
      chat_ref: chat_ref,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      TelegramDestination,
      [attrs],
      on_conflict: [set: [updated_at: now]],
      conflict_target: [:telegram_account_id, :chat_ref]
    )

    Repo.get_by!(TelegramDestination, telegram_account_id: account_id, chat_ref: chat_ref)
  end

  defp build_telegram_channel_config(config, chat_ref) do
    parse_mode = get_value(config, "parse_mode") || "HTML"
    %{"chat_ref" => chat_ref, "parse_mode" => parse_mode}
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError ->
      Map.get(map, key)
  end

  defp get_value(_, _), do: nil

  defp put_value(map, key, value) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.put(map, key, value)
    else
      Map.put(map, String.to_atom(key), value)
    end
  rescue
    ArgumentError ->
      Map.put(map, key, value)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
