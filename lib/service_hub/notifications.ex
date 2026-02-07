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
    |> Repo.all()
  end

  @doc """
  Gets a single notification channel by ID for the current user.
  """
  def get_channel!(%Scope{} = scope, id) do
    NotificationChannel
    |> where([c], c.id == ^id and c.user_id == ^scope.user.id)
    |> Repo.one!()
  end

  @doc """
  Creates a new notification channel.
  """
  def create_channel(%Scope{} = scope, attrs) do
    %NotificationChannel{user_id: scope.user.id}
    |> NotificationChannel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification channel.
  """
  def update_channel(%Scope{} = scope, %NotificationChannel{} = channel, attrs) do
    true = channel.user_id == scope.user.id

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
end
