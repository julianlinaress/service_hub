defmodule ServiceHub.Notifications.DeliveryAttemptsTest do
  use ServiceHub.DataCase

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.DeliveryAttempt
  alias ServiceHub.Notifications.DeliveryAttempts
  alias ServiceHub.Services.Service
  alias ServiceHub.Deployments.Deployment

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  setup do
    scope = user_scope_fixture()
    provider = provider_fixture(scope)

    service =
      Repo.insert!(%Service{
        name: "Delivery Service",
        provider_id: provider.id,
        owner: "owner",
        repo: "repo",
        healthcheck_endpoint_template: "https://{{host}}/health"
      })

    deployment =
      Repo.insert!(%Deployment{
        service_id: service.id,
        name: "delivery-deployment",
        host: "delivery.example.com",
        env: "production",
        automatic_checks_enabled: true,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

    {:ok, channel} =
      Notifications.create_channel(scope, %{
        name: "Test Telegram",
        provider: "telegram",
        config: %{"token" => "123456:ABC-DEF", "chat_ref" => "@alerts"}
      })

    event_id = Ecto.UUID.generate()

    :ok =
      ServiceHub.Notifications.Events.emit(
        "health.alert",
        %{
          "service_id" => service.id,
          "deployment_id" => deployment.id,
          "check_type" => "health",
          "message" => "boom",
          "metadata" => %{"host" => deployment.host, "env" => deployment.env}
        },
        id: event_id,
        tags: %{"source" => "automatic"}
      )

    event = %{
      "id" => event_id,
      "name" => "health.alert",
      "payload" => %{
        "service_id" => service.id,
        "deployment_id" => deployment.id,
        "check_type" => "health",
        "message" => "boom",
        "metadata" => %{"host" => deployment.host, "env" => deployment.env}
      },
      "tags" => %{"source" => "automatic"}
    }

    %{channel: channel, event: event, event_id: event_id}
  end

  test "upsert_pending_attempt/3 creates deduplicated pending attempt", %{
    channel: channel,
    event: event
  } do
    assert {:ok, attempt_1} =
             DeliveryAttempts.upsert_pending_attempt(event["id"], channel, event)

    assert {:ok, attempt_2} =
             DeliveryAttempts.upsert_pending_attempt(event["id"], channel, event)

    assert attempt_1.delivery_attempt_key == attempt_2.delivery_attempt_key

    assert Repo.aggregate(DeliveryAttempt, :count) == 1
  end

  test "mark attempt lifecycle fields", %{channel: channel, event: event} do
    {:ok, attempt} = DeliveryAttempts.upsert_pending_attempt(event["id"], channel, event)

    assert {:ok, started} = DeliveryAttempts.mark_attempt_started(attempt, 2)
    assert started.status == "in_progress"
    assert started.attempt_count == 2
    assert started.attempted_at

    assert {:ok, delivered} =
             DeliveryAttempts.mark_attempt_delivered(started, %{
               "provider_message_id" => "42",
               "provider_response_code" => "200",
               "provider_response" => %{"ok" => true}
             })

    assert delivered.status == "delivered"
    assert delivered.provider_message_id == "42"
    assert delivered.provider_response_code == "200"
    assert delivered.delivered_at

    assert {:ok, failed} =
             DeliveryAttempts.mark_attempt_failed(delivered, :timeout, %{
               "provider_response_code" => "504",
               "provider_response" => %{"ok" => false}
             })

    assert failed.status == "failed"
    assert failed.error_code == "timeout"
    assert failed.provider_response_code == "504"
    assert failed.failed_at
  end
end
