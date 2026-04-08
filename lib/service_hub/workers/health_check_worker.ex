defmodule ServiceHub.Workers.HealthCheckWorker do
  @moduledoc """
  Oban worker that executes a health check for a single deployment.

  Enqueued by `CheckEnqueuerWorker` when an automation target is due.
  Uses `max_attempts: 1` because retries are managed via `automation_targets`
  (exponential backoff, auto-pause after consecutive failures).
  """
  use Oban.Worker, queue: :health_checks, max_attempts: 1

  require Logger
  alias ServiceHub.Workers.CheckHelpers
  alias ServiceHub.Deployments.{Deployment, PubSub}
  alias ServiceHub.Checks.{Health, NotificationTrigger}
  alias ServiceHub.Repo

  @automation_id "deployment_health"
  @max_failures 3
  @backoff_curve {2, 2, 120}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"target_id" => target_id}}) do
    target = CheckHelpers.get_target(@automation_id, target_id)

    if is_nil(target) do
      Logger.warning("HealthCheckWorker: target not found for deployment #{target_id}")
      :ok
    else
      execute_check(target, target_id)
    end
  end

  defp execute_check(target, target_id) do
    deployment =
      Repo.get(Deployment, target_id)
      |> Repo.preload(service: :provider)

    started_at = DateTime.utc_now(:microsecond)

    result =
      case deployment do
        nil -> {:error, :deployment_not_found}
        dep -> Health.run(dep, dep.service)
      end

    finished_at = DateTime.utc_now(:microsecond)
    duration_ms = DateTime.diff(finished_at, started_at, :millisecond)

    {status, summary, error} = CheckHelpers.normalize_health_result(result)

    CheckHelpers.update_target_state(target, status, error, finished_at,
      max_failures: @max_failures,
      backoff_curve: @backoff_curve
    )

    CheckHelpers.insert_run_record(
      target,
      status,
      summary,
      error,
      started_at,
      finished_at,
      duration_ms
    )

    if deployment do
      PubSub.broadcast_check_completed(deployment, :health)
      NotificationTrigger.trigger_health_notification(deployment, result, "automatic")
    end

    :ok
  end
end
