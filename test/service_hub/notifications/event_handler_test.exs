defmodule ServiceHub.Notifications.EventHandlerTest do
  use ServiceHub.DataCase, async: false

  use Oban.Testing, repo: ServiceHub.Repo
  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.DeliveryAttempt
  alias ServiceHub.Notifications.EventHandler
  alias ServiceHub.Notifications.Events
  alias ServiceHub.Services.Service

  setup do
    scope = user_scope_fixture()
    provider = provider_fixture(scope)

    service =
      Repo.insert!(%Service{
        name: "Test Service",
        provider_id: provider.id,
        owner: "owner",
        repo: "repo",
        healthcheck_endpoint_template: "https://{{host}}/health"
      })

    {:ok, channel} =
      Notifications.create_channel(scope, %{
        name: "Test Telegram",
        provider: "telegram",
        config: %{"token" => "123456:ABC-DEF", "chat_ref" => "@alerts"}
      })

    rules = %{
      "health" => %{"warning" => true, "alert" => true, "recovery" => false}
    }

    {:ok, rule} =
      Notifications.create_service_rule(scope, %{
        "service_id" => service.id,
        "channel_id" => channel.id,
        "enabled" => true,
        "rules" => rules,
        "notify_on_manual" => true
      })

    %{scope: scope, service: service, channel: channel, rule: rule}
  end

  defp emit_and_fetch(event_name, service_id, tags \\ %{"source" => "automatic"}, check_type \\ "health") do
    event_id = Ecto.UUID.generate()

    :ok =
      Events.emit(
        event_name,
        %{"service_id" => service_id, "check_type" => check_type},
        id: event_id,
        tags: tags
      )

    %{
      "id" => event_id,
      "name" => event_name,
      "payload" => %{"service_id" => service_id, "check_type" => check_type},
      "tags" => tags
    }
  end

  describe "enqueue_deliveries/1" do
    test "creates a delivery attempt and enqueues a delivery job", %{
      service: service,
      channel: channel
    } do
      event = emit_and_fetch("health.alert", service.id)

      assert :ok = EventHandler.enqueue_deliveries(event)

      attempts = Repo.all(DeliveryAttempt)
      assert length(attempts) == 1
      assert hd(attempts).status == "pending"
      assert hd(attempts).channel_id == channel.id

      assert_enqueued(worker: ServiceHub.Workers.NotificationDeliveryWorker)
    end

    test "respects the only_channel_id option", %{scope: scope, service: service} do
      {:ok, second_channel} =
        Notifications.create_channel(scope, %{
          name: "Second Channel",
          provider: "telegram",
          config: %{"token" => "999999:XYZ", "chat_ref" => "@other"}
        })

      event = emit_and_fetch("health.alert", service.id)

      assert :ok = EventHandler.enqueue_deliveries(event, only_channel_id: second_channel.id)

      attempts = Repo.all(DeliveryAttempt)
      assert length(attempts) == 1
      assert hd(attempts).channel_id == second_channel.id
    end

    test "skips channels when no matching rule", %{service: service} do
      event = emit_and_fetch("version.alert", service.id, %{"source" => "automatic"}, "version")

      assert :ok = EventHandler.enqueue_deliveries(event)

      assert Repo.aggregate(DeliveryAttempt, :count) == 0
    end

    test "skips manual source when notify_on_manual is false", %{
      scope: scope,
      service: service,
      rule: rule
    } do
      {:ok, _rule} = Notifications.update_service_rule(scope, rule, %{"notify_on_manual" => false})

      event = emit_and_fetch("health.alert", service.id, %{"source" => "manual"})

      assert :ok = EventHandler.enqueue_deliveries(event)

      assert Repo.aggregate(DeliveryAttempt, :count) == 0
    end

    test "returns :ok when event_id is nil" do
      event = %{"name" => "health.alert", "payload" => %{}, "tags" => %{}}

      assert :ok = EventHandler.enqueue_deliveries(event)
    end
  end
end
