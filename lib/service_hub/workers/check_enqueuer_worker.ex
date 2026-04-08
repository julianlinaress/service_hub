defmodule ServiceHub.Workers.CheckEnqueuerWorker do
  @moduledoc """
  Oban cron worker that polls `automation_targets` for due checks and
  enqueues individual `HealthCheckWorker` / `VersionCheckWorker` jobs.

  Runs every minute via Oban Cron plugin. Replaces the custom GenServer
  scheduler's polling loop.

  Responsibilities:
  - Query due targets per automation type (joins with eligible deployments)
  - Insert Oban jobs with unique constraints to prevent double-enqueue
  - Set `running_at` on claimed targets
  - Detect and clear stale `running_at` leases (>10 min)
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  require Logger
  alias ServiceHub.Automations.AutomationTarget
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Repo
  import Ecto.Query

  @stale_lease_minutes 10

  @impl Oban.Worker
  def perform(_job) do
    clear_stale_leases()
    enqueue_health_checks()
    enqueue_version_checks()
    :ok
  end

  defp enqueue_health_checks do
    eligible_query =
      from(d in Deployment,
        where: d.automatic_checks_enabled == true,
        select: d.id
      )

    due_targets = query_due_targets("deployment_health", eligible_query)

    Logger.info("CheckEnqueuer: #{length(due_targets)} due health check targets")

    Enum.each(due_targets, fn target ->
      changeset =
        ServiceHub.Workers.HealthCheckWorker.new(
          %{target_id: target.target_id},
          unique: [period: 300, keys: [:args]]
        )

      case Oban.insert(changeset) do
        {:ok, %{conflict?: false}} ->
          mark_running(target)

        {:ok, %{conflict?: true}} ->
          Logger.debug(
            "CheckEnqueuer: skipped duplicate health check for deployment #{target.target_id}"
          )

        {:error, reason} ->
          Logger.error(
            "CheckEnqueuer: failed to enqueue health check for deployment #{target.target_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp enqueue_version_checks do
    eligible_query =
      from(d in Deployment,
        where: d.automatic_checks_enabled == true,
        where: d.version_check_enabled == true,
        select: d.id
      )

    due_targets = query_due_targets("deployment_version", eligible_query)

    Logger.info("CheckEnqueuer: #{length(due_targets)} due version check targets")

    Enum.each(due_targets, fn target ->
      changeset =
        ServiceHub.Workers.VersionCheckWorker.new(
          %{target_id: target.target_id},
          unique: [period: 300, keys: [:args]]
        )

      case Oban.insert(changeset) do
        {:ok, %{conflict?: false}} ->
          mark_running(target)

        {:ok, %{conflict?: true}} ->
          Logger.debug(
            "CheckEnqueuer: skipped duplicate version check for deployment #{target.target_id}"
          )

        {:error, reason} ->
          Logger.error(
            "CheckEnqueuer: failed to enqueue version check for deployment #{target.target_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp query_due_targets(automation_id, eligible_query) do
    now = DateTime.utc_now()

    from(at in AutomationTarget,
      join: e in subquery(eligible_query),
      on: e.id == at.target_id,
      where: at.automation_id == ^automation_id,
      where: at.target_type == "deployment",
      where: at.enabled == true,
      where: is_nil(at.paused_at),
      where: is_nil(at.running_at),
      where: is_nil(at.next_run_at) or at.next_run_at <= ^now,
      order_by: [asc_nulls_first: at.next_run_at, asc: at.id]
    )
    |> Repo.all()
  end

  defp mark_running(target) do
    now = DateTime.utc_now(:microsecond)

    from(at in AutomationTarget,
      where: at.id == ^target.id,
      update: [
        set: [
          running_at: ^now,
          last_started_at: ^now,
          updated_at: ^now
        ]
      ]
    )
    |> Repo.update_all([])
  end

  defp clear_stale_leases do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_lease_minutes * 60, :second)

    {count, _} =
      from(at in AutomationTarget,
        where: not is_nil(at.running_at),
        where: at.running_at < ^cutoff
      )
      |> Repo.update_all(set: [running_at: nil, updated_at: DateTime.utc_now(:microsecond)])

    if count > 0 do
      Logger.warning("CheckEnqueuer: cleared #{count} stale leases (>#{@stale_lease_minutes}min)")
    end
  end
end
