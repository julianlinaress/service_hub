defmodule ServiceHub.Notifications.Rules do
  @moduledoc false
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.ServiceNotificationRule
  alias ServiceHub.Repo
  alias ServiceHub.Services.Service

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

  def create_service_rule(%Scope{} = scope, attrs) do
    with {:ok, _service} <- verify_service_access(scope, attrs["service_id"]),
         {:ok, _channel} <- verify_channel_access(scope, attrs["channel_id"]) do
      %ServiceNotificationRule{}
      |> ServiceNotificationRule.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_service_rule(%Scope{} = scope, %ServiceNotificationRule{} = rule, attrs) do
    rule = Repo.preload(rule, [:service, :channel])

    with {:ok, _service} <- verify_service_access(scope, rule.service_id),
         {:ok, _channel} <- verify_channel_access(scope, rule.channel_id) do
      rule
      |> ServiceNotificationRule.changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_service_rule(%Scope{} = scope, %ServiceNotificationRule{} = rule) do
    rule = Repo.preload(rule, [:service, :channel])

    with {:ok, _service} <- verify_service_access(scope, rule.service_id),
         {:ok, _channel} <- verify_channel_access(scope, rule.channel_id) do
      Repo.delete(rule)
    end
  end

  def change_service_rule(%Scope{} = _scope, %ServiceNotificationRule{} = rule, attrs \\ %{}) do
    ServiceNotificationRule.changeset(rule, attrs)
  end

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
