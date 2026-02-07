defmodule ServiceHub.Checks.NotificationTrigger do
  @moduledoc """
  Shared logic for triggering notifications after health and version checks.
  Used by both automatic checks (automations) and manual checks (UI).
  """

  alias ServiceHub.Notifications.EventHandler
  alias ServiceHub.Notifications.Events
  alias ServiceHub.Notifications.DeploymentNotificationState
  alias ServiceHub.Repo

  @doc """
  Trigger health check notification based on status change.
  Source should be "automatic" or "manual".
  """
  def trigger_health_notification(deployment, result, source \\ "automatic") do
    # Determine current status
    current_status =
      case result do
        {:ok, _} -> "ok"
        {:warning, _reason, _} -> "warning"
        {:error, _reason, _} -> "down"
      end

    # Get or create state tracking record
    state =
      Repo.get_by(DeploymentNotificationState,
        deployment_id: deployment.id,
        check_type: "health"
      ) ||
        %DeploymentNotificationState{
          deployment_id: deployment.id,
          check_type: "health"
        }

    previous_status = state.last_status

    # Determine if we should notify and what severity
    {should_notify, severity, message} =
      case {previous_status, current_status} do
        # First check ever - notify about current state
        {nil, "ok"} ->
          {true, "info", "Health check passed (initial)"}

        {nil, "warning"} ->
          {true, "warning", "Health check warning (initial): #{format_result(result)}"}

        {nil, "down"} ->
          {true, "alert", "Health check failed (initial): #{format_result(result)}"}

        # Status unchanged - no notification
        {same, same} ->
          {false, nil, nil}

        # Recovery: was down or warning, now ok
        {prev, "ok"} when prev in ["down", "warning"] ->
          {true, "recovery", "Health check recovered"}

        # Degradation: was ok, now warning
        {"ok", "warning"} ->
          {true, "warning", "Health check warning: #{format_result(result)}"}

        # Failure: was ok or warning, now down
        {prev, "down"} when prev in ["ok", "warning"] ->
          {true, "alert", "Health check failed: #{format_result(result)}"}

        # Warning to down
        {"warning", "down"} ->
          {true, "alert", "Health check failed: #{format_result(result)}"}

        # Down to warning (still problematic)
        {"down", "warning"} ->
          {true, "warning", "Health check still has issues: #{format_result(result)}"}

        # Any other change - treat as info
        _ ->
          {true, "change",
           "Health check status changed from #{previous_status} to #{current_status}"}
      end

    # Only emit if there's a change
    if should_notify do
      event_payload = %{
        "service_id" => deployment.service_id,
        "deployment_id" => deployment.id,
        "check_type" => "health",
        "message" => message,
        "metadata" => %{
          "status" => current_status,
          "previous_status" => previous_status,
          "host" => deployment.host,
          "env" => deployment.env
        }
      }

      event_tags = %{
        "source" => source
      }

      event_name = "health.#{severity}"
      Events.emit(event_name, event_payload, tags: event_tags)

      # Handle event routing and delivery
      EventHandler.handle_event(%{
        name: event_name,
        payload: event_payload,
        tags: event_tags
      })

      # Update state
      state
      |> DeploymentNotificationState.changeset(%{
        last_status: current_status,
        last_notified_at: DateTime.utc_now()
      })
      |> Repo.insert_or_update!()
    else
      # Update state without notifying
      state
      |> DeploymentNotificationState.changeset(%{
        last_status: current_status
      })
      |> Repo.insert_or_update!()
    end
  end

  @doc """
  Trigger version check notification based on version change.
  Source should be "automatic" or "manual".
  """
  def trigger_version_notification(deployment, result, source \\ "automatic") do
    # Get or create state tracking record
    state =
      Repo.get_by(DeploymentNotificationState,
        deployment_id: deployment.id,
        check_type: "version"
      ) ||
        %DeploymentNotificationState{
          deployment_id: deployment.id,
          check_type: "version"
        }

    previous_version = state.last_version

    # Determine if we should notify and what severity
    {should_notify, severity, message, current_version} =
      case result do
        {:ok, updated_deployment} ->
          new_version = updated_deployment.current_version

          cond do
            # First check or no previous version
            previous_version == nil && new_version != nil ->
              {true, "change", "Version detected: #{new_version}", new_version}

            # Version changed
            previous_version != new_version && new_version != nil ->
              {true, "change", "Version changed from #{previous_version} to #{new_version}",
               new_version}

            # Version unchanged
            true ->
              {false, nil, nil, new_version}
          end

        {:skipped, updated_deployment} ->
          # No notification for skipped checks
          {false, nil, nil, updated_deployment.current_version}

        {:error, reason, updated_deployment} ->
          # Notify on version check failures
          {true, "alert", "Version check failed: #{inspect(reason)}",
           updated_deployment.current_version}
      end

    # Only emit if there's a change
    if should_notify do
      event_payload = %{
        "service_id" => deployment.service_id,
        "deployment_id" => deployment.id,
        "check_type" => "version",
        "message" => message,
        "metadata" => %{
          "version" => current_version,
          "previous_version" => previous_version,
          "host" => deployment.host,
          "env" => deployment.env
        }
      }

      event_tags = %{
        "source" => source
      }

      event_name = "version.#{severity}"
      Events.emit(event_name, event_payload, tags: event_tags)

      # Handle event routing and delivery
      EventHandler.handle_event(%{
        name: event_name,
        payload: event_payload,
        tags: event_tags
      })

      # Update state
      state
      |> DeploymentNotificationState.changeset(%{
        last_version: current_version,
        last_notified_at: DateTime.utc_now()
      })
      |> Repo.insert_or_update!()
    else
      # Update state without notifying
      if current_version do
        state
        |> DeploymentNotificationState.changeset(%{
          last_version: current_version
        })
        |> Repo.insert_or_update!()
      end
    end
  end

  # Private helpers

  defp format_result({:ok, _}), do: "passed"
  defp format_result({:warning, reason, _}), do: format_reason(reason)
  defp format_result({:error, reason, _}), do: format_reason(reason)

  defp format_reason({:unexpected_status, status}), do: "unexpected status #{status}"
  defp format_reason({:error, reason}), do: inspect(reason)
end
