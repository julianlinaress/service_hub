defmodule ServiceHub.Automations.Runner do
  @moduledoc """
  Executes automation tasks under a Task.Supervisor with concurrency limits and timeouts.

  Responsibilities:
  - Execute automation run/1 callbacks with timeout
  - Update automation_targets state on completion
  - Insert automation_runs audit records
  - Handle crashes and timeouts gracefully
  - Calculate backoff intervals for failures
  - Broadcast PubSub updates on completion
  """
  require Logger
  alias ServiceHub.Automations.{AutomationTarget, AutomationRun, Behaviour}
  alias ServiceHub.Deployments.{Deployment, PubSub}
  alias ServiceHub.Repo
  import Ecto.Query

  @doc """
  Executes an automation for a target.

  This function is typically called from the Scheduler after claiming a target.
  It runs the automation with a timeout, updates state, and logs the result.
  """
  def execute(automation_module, %AutomationTarget{} = target) do
    started_at = DateTime.utc_now(:microsecond)
    timeout_ms = Behaviour.timeout_seconds(automation_module) * 1000
    max_failures = Behaviour.max_failures(automation_module)

    Logger.info(
      "Automation starting: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} timeout=#{timeout_ms}ms"
    )

    # Execute with timeout
    result =
      try do
        task = Task.async(fn -> automation_module.run(target) end)

        case Task.yield(task, timeout_ms) || Task.shutdown(task) do
          {:ok, result} ->
            result

          nil ->
            {:error, :timeout}
        end
      rescue
        error ->
          Logger.error(
            "Automation crashed: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} error=#{inspect(error)}"
          )

          {:error, {:exception, error}}
      end

    finished_at = DateTime.utc_now(:microsecond)
    duration_ms = DateTime.diff(finished_at, started_at, :millisecond)

    # Update target state and insert run record
    update_target_state(target, result, finished_at, duration_ms, max_failures, automation_module)

    # Log completion
    log_completion(target, result, duration_ms)

    result
  end

  defp update_target_state(target, result, finished_at, duration_ms, max_failures, automation_module) do
    {status, summary, error} = normalize_result(result)

    # Calculate next_run_at based on success or failure
    next_run_at =
      case status do
        s when s in ["ok", "warning"] ->
          # Success: use normal interval
          DateTime.add(DateTime.utc_now(:microsecond), target.interval_minutes * 60, :second)

        _ ->
          # Failure: use backoff
          calculate_backoff(target.consecutive_failures + 1, target.interval_minutes, automation_module)
      end

    consecutive_failures =
      case status do
        s when s in ["ok", "warning"] -> 0
        _ -> target.consecutive_failures + 1
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

    # Update automation_targets
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

    # Insert automation_runs record
    %AutomationRun{}
    |> AutomationRun.changeset(%{
      automation_id: target.automation_id,
      target_type: target.target_type,
      target_id: target.target_id,
      status: status,
      started_at: target.running_at,
      finished_at: finished_at,
      duration_ms: duration_ms,
      summary: summary,
      error: error,
      attempt: target.consecutive_failures + 1,
      node: to_string(node())
    })
    |> Repo.insert()

    # Broadcast PubSub update if this is a deployment check
    broadcast_deployment_update(target)
  end

  defp broadcast_deployment_update(%{target_type: "deployment", target_id: target_id, automation_id: automation_id}) do
    # Fetch the deployment to broadcast
    case Repo.get(Deployment, target_id) do
      nil ->
        :ok

      deployment ->
        check_type =
          case automation_id do
            "deployment_health" -> :health
            "deployment_version" -> :version
            _ -> :other
          end

        PubSub.broadcast_check_completed(deployment, check_type)
    end
  end

  defp broadcast_deployment_update(_target), do: :ok

  defp normalize_result({:ok, summary}) when is_binary(summary), do: {"ok", summary, nil}
  defp normalize_result({:ok, _}), do: {"ok", "Success", nil}
  defp normalize_result({:warning, summary}) when is_binary(summary), do: {"warning", summary, nil}
  defp normalize_result({:warning, _}), do: {"warning", "Warning", nil}
  defp normalize_result({:error, :timeout}), do: {"timeout", nil, "Execution timeout"}

  defp normalize_result({:error, reason}) do
    error_str = inspect(reason)
    {"error", nil, error_str}
  end

  defp normalize_result(_), do: {"error", nil, "Unknown result format"}

  defp calculate_backoff(failures, base_interval, automation_module) do
    {base_minutes, multiplier, cap_minutes} = Behaviour.backoff_curve(automation_module)

    # Exponential backoff: base * multiplier^failures, capped
    backoff_minutes =
      min(
        base_minutes * :math.pow(multiplier, failures - 1),
        cap_minutes
      )
      |> round()

    # Never backoff less than the normal interval
    backoff_minutes = max(backoff_minutes, base_interval)

    DateTime.add(DateTime.utc_now(:microsecond), backoff_minutes * 60, :second)
  end

  defp log_completion(target, result, duration_ms) do
    case result do
      {:ok, _} ->
        Logger.info(
          "Automation completed: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} duration=#{duration_ms}ms status=ok"
        )

      {:warning, _} ->
        Logger.info(
          "Automation completed: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} duration=#{duration_ms}ms status=warning"
        )

      {:error, reason} ->
        Logger.error(
          "Automation failed: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} duration=#{duration_ms}ms status=error consecutive_failures=#{target.consecutive_failures + 1} error=#{inspect(reason)}"
        )
    end
  end
end
