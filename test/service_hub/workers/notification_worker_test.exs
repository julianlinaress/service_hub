defmodule ServiceHub.Workers.NotificationWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  alias ServiceHub.Notifications
  alias ServiceHub.Workers.NotificationWorker

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  alias ServiceHub.Services.Service

  describe "perform/1" do
    test "enqueues delivery attempt jobs from persisted event" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      service =
        Repo.insert!(%Service{
          name: "Worker Service",
          provider_id: provider.id,
          owner: "owner",
          repo: "repo",
          healthcheck_endpoint_template: "https://{{host}}/health"
        })

      {:ok, channel} =
        Notifications.create_channel(scope, %{
          name: "Telegram Worker",
          provider: "telegram",
          config: %{"token" => "123456:ABC-DEF", "chat_ref" => "@alerts"}
        })

      {:ok, _rule} =
        Notifications.create_service_rule(scope, %{
          "service_id" => service.id,
          "channel_id" => channel.id,
          "enabled" => true,
          "notify_on_manual" => true,
          "rules" => %{
            "health" => %{
              "alert" => true,
              "warning" => true,
              "recovery" => true,
              "change" => true
            }
          }
        })

      event_id = Ecto.UUID.generate()

      :ok =
        ServiceHub.Notifications.Events.emit(
          "health.alert",
          %{
            "service_id" => service.id,
            "deployment_id" => 99,
            "check_type" => "health",
            "message" => "Health check failed",
            "metadata" => %{"host" => "test.example.com", "env" => "test"}
          },
          id: event_id,
          tags: %{"source" => "automatic"}
        )

      event = %{
        "id" => event_id,
        "name" => "health.alert",
        "payload" => %{
          "service_id" => service.id,
          "deployment_id" => 99,
          "check_type" => "health",
          "message" => "Health check failed",
          "metadata" => %{"host" => "test.example.com", "env" => "test"}
        },
        "tags" => %{"source" => "automatic"}
      }

      assert :ok = perform_job(NotificationWorker, %{event: event})

      assert_enqueued(worker: ServiceHub.Workers.NotificationDeliveryWorker)

      assert Repo.get(ServiceHub.Notifications.Event, event_id)
    end
  end

  describe "backoff/1" do
    test "returns exponential backoff" do
      assert NotificationWorker.backoff(%Oban.Job{attempt: 1}) == 30
      assert NotificationWorker.backoff(%Oban.Job{attempt: 2}) == 90
    end
  end
end
