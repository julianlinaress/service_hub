defmodule ServiceHub.Workers.CheckHelpers do
  @moduledoc """
  Shared helpers for health and version check Oban workers.

  Handles automation_target state updates, audit record insertion,
  backoff calculation, and result normalization.
  """
  require Logger
  alias ServiceHub.Automations.{AutomationTarget, AutomationRun}
  alias ServiceHub.Repo
  import Ecto.Query

  @doc """
  Updates automation_target state after a check completes.

  Clears `running_at`, updates `next_run_at` (with backoff on failure),
  increments `consecutive_failures`, and auto-pauses after max failures.

  ## Options
    * `:max_failures` - consecutive failures before auto-pause (required)
    * `:backoff_curve` - `{base_minutes, multiplier, cap_minutes}` (required)
  """
  def update_target_state(target, status, error, finished_at, opts) do
    max_failures = Keyword.fetch!(opts, :max_failures)
    backoff_curve = Keyword.fetch!(opts, :backoff_curve)

    consecutive_failures =
      if status in ["ok", "warning"], do: 0, else: target.consecutive_failures + 1

    next_run_at =
      if status in ["ok", "warning"] do
        DateTime.add(DateTime.utc_now(:microsecond), target.interval_minutes * 60, :second)
      else
        calculate_backoff(consecutive_failures, target.interval_minutes, backoff_curve)
      end

    paused_at =
      if consecutive_failures >= max_failures do
        Logger.warning(
          "Automation auto-paused: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} failures=#{consecutive_failures}"
        )

        DateTime.utc_now(:microsecond)
      else
        nil
      end

    from(at in AutomationTarget,
      where: at.id == ^target.id,
      update: [
        set: [
          running_at: nil,
          last_finished_at: ^finished_at,
          last_status: ^status,
          last_error: ^error,
          consecutive_failures: ^consecutive_failures,
          next_run_at: ^next_run_at,
          paused_at: ^paused_at,
          updated_at: ^DateTime.utc_now(:microsecond)
        ]
      ]
    )
    |> Repo.update_all([])
  end

  @doc """
  Inserts an automation_runs audit record.
  """
  def insert_run_record(target, status, summary, error, started_at, finished_at, duration_ms) do
    %AutomationRun{}
    |> AutomationRun.changeset(%{
      automation_id: target.automation_id,
      target_type: target.target_type,
      target_id: target.target_id,
      status: status,
      started_at: started_at,
      finished_at: finished_at,
      duration_ms: duration_ms,
      summary: summary,
      error: error,
      attempt: target.consecutive_failures + 1,
      node: to_string(node())
    })
    |> Repo.insert()
  end

  @doc """
  Calculates the next run time using exponential backoff.

  Backoff: `base * multiplier^(failures-1)`, capped at `cap_minutes`,
  never less than the target's normal interval.
  """
  def calculate_backoff(failures, base_interval, {base_minutes, multiplier, cap_minutes}) do
    backoff_minutes =
      min(
        base_minutes * :math.pow(multiplier, failures - 1),
        cap_minutes
      )
      |> round()

    backoff_minutes = max(backoff_minutes, base_interval)

    DateTime.add(DateTime.utc_now(:microsecond), backoff_minutes * 60, :second)
  end

  @doc """
  Normalizes a health check result to `{status, summary, error}`.
  """
  def normalize_health_result({:ok, _updated_deployment}),
    do: {"ok", "Health check passed", nil}

  def normalize_health_result({:warning, reason, _updated_deployment}),
    do: {"warning", "Health check warning: #{inspect(reason)}", nil}

  def normalize_health_result({:error, reason, _updated_deployment}),
    do: {"error", nil, inspect(reason)}

  def normalize_health_result({:error, reason}),
    do: {"error", nil, inspect(reason)}

  @doc """
  Normalizes a version check result to `{status, summary, error}`.
  """
  def normalize_version_result({:ok, _updated_deployment}),
    do: {"ok", "Version check passed", nil}

  def normalize_version_result({:skipped, _updated_deployment}),
    do: {"ok", "Version check skipped (disabled)", nil}

  def normalize_version_result({:error, reason, _updated_deployment}),
    do: {"warning", "Version check failed: #{inspect(reason)}", nil}

  def normalize_version_result({:error, reason}),
    do: {"error", nil, inspect(reason)}

  @doc """
  Fetches an automation target by automation_id and target_id.
  """
  def get_target(automation_id, target_id) do
    from(at in AutomationTarget,
      where:
        at.automation_id == ^automation_id and
          at.target_type == "deployment" and
          at.target_id == ^target_id
    )
    |> Repo.one()
  end
end
