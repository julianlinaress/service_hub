defmodule ServiceHub.Deployments do
  @moduledoc """
  Deployment management for services. Health checks are mandatory (with per-deployment
  expectations); version checks are optional and can be toggled per deployment.
  """
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Automations.AutomationTarget
  alias ServiceHub.Repo
  alias ServiceHub.Services.Service

  def list_recent_deployments(%Scope{} = scope, limit \\ 10) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :service))
    |> join(:inner, [_d, s], p in assoc(s, :provider))
    |> where([d, _s, p], not is_nil(d.last_health_checked_at) and p.user_id == ^scope.user.id)
    |> preload([_d, _s, _p], service: :provider)
    |> order_by([d], desc: d.last_health_checked_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_deployments_for_service(%Scope{} = scope, service_id) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :service))
    |> join(:inner, [_d, s], p in assoc(s, :provider))
    |> where([_d, s, p], s.id == ^service_id and p.user_id == ^scope.user.id)
    |> preload([d, _s, _p], service: :provider)
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  def get_deployment!(%Scope{} = scope, id) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :service))
    |> join(:inner, [_d, s], p in assoc(s, :provider))
    |> where([d, _s, p], d.id == ^id and p.user_id == ^scope.user.id)
    |> preload([d, _s, _p], service: :provider)
    |> Repo.one!()
  end

  def create_deployment(%Scope{} = scope, attrs) do
    with {:ok, service} <- fetch_service(scope, service_id_from_attrs(attrs)),
         changeset <- Deployment.changeset(%Deployment{service_id: service.id}, attrs),
         {:ok, deployment} <- Repo.insert(changeset) do
      # Sync automation targets after creation
      sync_automation_targets(deployment)
      {:ok, Repo.preload(deployment, service: :provider)}
    end
  end

  def update_deployment(%Scope{} = scope, %Deployment{} = deployment, attrs) do
    deployment = preload_service(deployment)
    true = deployment.service.provider.user_id == scope.user.id

    with {:ok, updated} <-
           deployment
           |> Deployment.changeset(attrs)
           |> Repo.update() do
      # Sync automation targets after update
      sync_automation_targets(updated)
      {:ok, updated}
    end
  end

  def delete_deployment(%Scope{} = scope, %Deployment{} = deployment) do
    deployment = preload_service(deployment)
    true = deployment.service.provider.user_id == scope.user.id

    Repo.transaction(fn ->
      # Delete automation targets first
      delete_automation_targets(deployment)
      # Then delete deployment
      case Repo.delete(deployment) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def change_deployment(%Scope{} = scope, %Deployment{} = deployment, attrs \\ %{}) do
    deployment = preload_service(deployment)

    cond do
      deployment.service && deployment.service.provider &&
          deployment.service.provider.user_id == scope.user.id ->
        Deployment.changeset(deployment, attrs)

      service_id = service_id_from_attrs(attrs || %{}) || deployment.service_id ->
        with {:ok, service} <- fetch_service(scope, service_id) do
          Deployment.changeset(%{deployment | service_id: service.id, service: service}, attrs)
        else
          _ ->
            deployment
            |> Deployment.changeset(attrs)
            |> Ecto.Changeset.add_error(:service_id, "is invalid for this user")
        end

      true ->
        deployment
        |> Deployment.changeset(attrs)
        |> Ecto.Changeset.add_error(:service_id, "is invalid for this user")
    end
  end

  defp fetch_service(%Scope{} = scope, service_id) when is_integer(service_id) do
    service =
      Service
      |> join(:inner, [s], p in assoc(s, :provider))
      |> where([s, p], s.id == ^service_id and p.user_id == ^scope.user.id)
      |> preload([_s, p], :provider)
      |> Repo.one()

    case service do
      %Service{} = service -> {:ok, service}
      _ -> {:error, :service_not_found}
    end
  end

  defp fetch_service(_, _), do: {:error, :service_not_found}

  defp preload_service(%Deployment{} = deployment) do
    Repo.preload(deployment, service: :provider)
  end

  defp service_id_from_attrs(%{"service_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp service_id_from_attrs(%{"service_id" => id}) when is_integer(id), do: id
  defp service_id_from_attrs(%{service_id: id}) when is_integer(id), do: id
  defp service_id_from_attrs(_), do: nil

  @doc """
  Syncs automation_targets for a deployment based on its automatic_checks_enabled
  and version_check_enabled settings.

  Creates/updates automation targets for:
  - deployment_health (if automatic_checks_enabled)
  - deployment_version (if automatic_checks_enabled AND version_check_enabled)

  Removes targets if checks are disabled.
  """
  def sync_automation_targets(%Deployment{} = deployment) do
    if deployment.automatic_checks_enabled do
      # Upsert health check target
      upsert_automation_target(
        "deployment_health",
        "deployment",
        deployment.id,
        deployment.check_interval_minutes
      )

      # Upsert version check target if version checks are enabled
      if deployment.version_check_enabled do
        upsert_automation_target(
          "deployment_version",
          "deployment",
          deployment.id,
          deployment.check_interval_minutes
        )
      else
        # Remove version check target if version checks are disabled
        delete_automation_target("deployment_version", "deployment", deployment.id)
      end
    else
      # Remove all automation targets if automatic checks are disabled
      delete_automation_targets(deployment)
    end
  end

  defp upsert_automation_target(automation_id, target_type, target_id, interval_minutes) do
    now = DateTime.utc_now(:microsecond)

    # Try to find existing target
    existing =
      from(at in AutomationTarget,
        where:
          at.automation_id == ^automation_id and at.target_type == ^target_type and
            at.target_id == ^target_id
      )
      |> Repo.one()

    case existing do
      nil ->
        # Create new target
        %AutomationTarget{}
        |> AutomationTarget.changeset(%{
          automation_id: automation_id,
          target_type: target_type,
          target_id: target_id,
          enabled: true,
          interval_minutes: interval_minutes,
          next_run_at: now
        })
        |> Repo.insert()

      %AutomationTarget{} = target ->
        # Update existing target
        attrs = %{
          enabled: true,
          interval_minutes: interval_minutes
        }

        attrs =
          if target.interval_minutes != interval_minutes or target.enabled == false or
               is_nil(target.next_run_at) do
            Map.put(attrs, :next_run_at, now)
          else
            attrs
          end

        target
        |> AutomationTarget.changeset(attrs)
        |> Repo.update()
    end
  end

  defp delete_automation_target(automation_id, target_type, target_id) do
    from(at in AutomationTarget,
      where:
        at.automation_id == ^automation_id and at.target_type == ^target_type and
          at.target_id == ^target_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Deletes all automation targets for a deployment.
  Used when deployment is deleted or automatic checks are disabled.
  """
  def delete_automation_targets(%Deployment{} = deployment) do
    from(at in AutomationTarget,
      where: at.target_type == "deployment" and at.target_id == ^deployment.id
    )
    |> Repo.delete_all()
  end
end
