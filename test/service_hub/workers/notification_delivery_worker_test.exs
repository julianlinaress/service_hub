defmodule ServiceHub.Workers.NotificationDeliveryWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  import Ecto.Query

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.DeliveryAttempts
  alias ServiceHub.Notifications.EventHandler
  alias ServiceHub.Workers.NotificationDeliveryWorker

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  alias ServiceHub.Services.Service

  setup do
    scope = user_scope_fixture()
    provider = provider_fixture(scope)

    service =
      Repo.insert!(%Service{
        name: "Notifier Service",
        provider_id: provider.id,
        owner: "owner",
        repo: "repo",
        healthcheck_endpoint_template: "https://{{host}}/health"
      })

    {:ok, channel} =
      Notifications.create_channel(scope, %{
        name: "Telegram Main",
        provider: "telegram",
        config: %{"token" => "123456:ABC-DEF", "chat_ref" => "@alerts"}
      })

    {:ok, rule} =
      Notifications.create_service_rule(scope, %{
        "service_id" => service.id,
        "channel_id" => channel.id,
        "enabled" => true,
        "notify_on_manual" => true,
        "rules" => %{
          "health" => %{"alert" => true, "warning" => true, "recovery" => true, "change" => true},
          "version" => %{"alert" => true, "warning" => true, "change" => true}
        }
      })

    event_id = Ecto.UUID.generate()

    :ok =
      ServiceHub.Notifications.Events.emit(
        "health.alert",
        %{
          "service_id" => service.id,
          "deployment_id" => 123,
          "check_type" => "health",
          "message" => "Health check failed",
          "metadata" => %{"host" => "app.example.com", "env" => "prod"}
        },
        id: event_id,
        tags: %{"source" => "automatic"}
      )

    event = %{
      "id" => event_id,
      "name" => "health.alert",
      "payload" => %{
        "service_id" => service.id,
        "deployment_id" => 123,
        "check_type" => "health",
        "message" => "Health check failed",
        "metadata" => %{"host" => "app.example.com", "env" => "prod"}
      },
      "tags" => %{"source" => "automatic"}
    }

    :ok = EventHandler.enqueue_deliveries(event)

    attempt =
      Repo.one!(
        from a in ServiceHub.Notifications.DeliveryAttempt,
          where: a.event_id == ^event_id,
          limit: 1
      )

    %{attempt: attempt, rule: rule}
  end

  test "marks attempt as delivered on notifier success", %{attempt: attempt} do
    Process.put(:notifier_client_response, {
      :ok,
      %{
        status: :delivered,
        provider_message_id: "tg-42",
        provider_response_code: "200",
        provider_response: %{"ok" => true}
      }
    })

    assert :ok = perform_job(NotificationDeliveryWorker, %{attempt_id: attempt.id})

    refreshed = DeliveryAttempts.get_attempt(attempt.id)
    assert refreshed.status == "delivered"
    assert refreshed.provider_message_id == "tg-42"
    assert refreshed.delivered_at
  end

  test "returns error for retryable failures", %{attempt: attempt} do
    Process.put(:notifier_client_response, {
      :error,
      %{
        status: :failed,
        retryable: true,
        error_code: "provider_timeout",
        error_message: "timeout",
        provider_response_code: "504",
        provider_response: %{"ok" => false}
      }
    })

    assert {:error, {:retryable_delivery_failure, "provider_timeout"}} =
             perform_job(NotificationDeliveryWorker, %{attempt_id: attempt.id})

    refreshed = DeliveryAttempts.get_attempt(attempt.id)
    assert refreshed.status == "failed"
    assert refreshed.error_code == "provider_timeout"
    assert refreshed.failed_at
  end

  test "persists permanent failures without retry", %{attempt: attempt} do
    Process.put(:notifier_client_response, {
      :error,
      %{
        status: :failed,
        retryable: false,
        error_code: "invalid_destination",
        error_message: "bad destination",
        provider_response_code: "400",
        provider_response: %{"ok" => false}
      }
    })

    assert :ok = perform_job(NotificationDeliveryWorker, %{attempt_id: attempt.id})

    refreshed = DeliveryAttempts.get_attempt(attempt.id)
    assert refreshed.status == "failed"
    assert refreshed.error_code == "invalid_destination"
    assert refreshed.failed_at
  end
end
