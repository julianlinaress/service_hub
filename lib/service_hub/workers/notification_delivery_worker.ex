defmodule ServiceHub.Workers.NotificationDeliveryWorker do
  @moduledoc """
  Oban worker that executes one concrete notification delivery attempt.

  This worker calls the external notifier service and persists the
  normalized result in `notification_delivery_attempts`.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias ServiceHub.Notifications.DeliveryAttempt
  alias ServiceHub.Notifications.DeliveryAttempts
  alias ServiceHub.Notifications.NotifierClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}, attempt: attempt_count, id: job_id}) do
    case DeliveryAttempts.get_attempt(attempt_id) do
      nil ->
        :ok

      %DeliveryAttempt{status: "delivered"} ->
        :ok

      %DeliveryAttempt{} = attempt ->
        execute_attempt(attempt, attempt_count, job_id)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(:math.pow(2, attempt) * 15)
  end

  defp execute_attempt(attempt, attempt_count, job_id) do
    {:ok, started_attempt} = DeliveryAttempts.mark_attempt_started(attempt, attempt_count, job_id)

    destination = get_in(started_attempt.destination_snapshot, ["resolved_destination"]) || %{}

    if destination["error_code"] == "telegram_not_connected" do
      error = %{
        error_code: "telegram_not_connected",
        error_message: "User has no active Telegram connection",
        retryable: false,
        provider_response: %{}
      }

      DeliveryAttempts.mark_attempt_failed(started_attempt, error, %{})
      :ok
    else
      request = build_request(started_attempt)

      case NotifierClient.deliver(request) do
        {:ok, response} ->
          DeliveryAttempts.mark_attempt_delivered(started_attempt, response)
          :ok

        {:error, %{retryable: true} = error} ->
          DeliveryAttempts.mark_attempt_failed(started_attempt, error, error.provider_response)
          {:error, {:retryable_delivery_failure, error.error_code}}

        {:error, error} ->
          DeliveryAttempts.mark_attempt_failed(started_attempt, error, error.provider_response)
          :ok
      end
    end
  end

  defp build_request(attempt) do
    payload_snapshot = attempt.payload_snapshot || %{}
    destination_snapshot = attempt.destination_snapshot || %{}

    event_payload = payload_snapshot["payload"] || %{}

    %{
      "delivery_attempt_key" => attempt.delivery_attempt_key,
      "provider" => attempt.provider,
      "destination" => destination_snapshot["resolved_destination"] || %{},
      "notification" => %{
        "event_name" => payload_snapshot["name"],
        "check_type" => event_payload["check_type"],
        "severity" => extract_severity(payload_snapshot["name"]),
        "message" => event_payload["message"],
        "service_id" => event_payload["service_id"],
        "deployment_id" => event_payload["deployment_id"],
        "metadata" => event_payload["metadata"] || %{}
      },
      "event" => %{
        "id" => payload_snapshot["id"],
        "name" => payload_snapshot["name"],
        "tags" => payload_snapshot["tags"] || %{}
      }
    }
  end

  defp extract_severity(event_name) when is_binary(event_name) do
    cond do
      String.contains?(event_name, "alert") -> "alert"
      String.contains?(event_name, "warning") -> "warning"
      String.contains?(event_name, "recovery") -> "recovery"
      String.contains?(event_name, "info") -> "info"
      true -> "info"
    end
  end

  defp extract_severity(_), do: "info"
end
