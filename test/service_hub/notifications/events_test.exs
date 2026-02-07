defmodule ServiceHub.Notifications.EventsTest do
  use ServiceHub.DataCase

  import Ecto.Query

  alias ServiceHub.Notifications.Event
  alias ServiceHub.Notifications.Events

  describe "emit/3" do
    test "persists event with tags and source metadata" do
      payload = %{"service_id" => 1, "message" => "ok"}

      assert :ok =
               Events.emit("health.info", payload,
                 tags: %{"source" => "automatic", "kind" => "health"},
                 actor: "scheduler"
               )

      event = Repo.one(from e in Event, order_by: [desc: e.inserted_at], limit: 1)

      assert event.name == "health.info"
      assert event.payload == payload
      assert event.tags == %{"source" => "automatic", "kind" => "health"}
      assert event.source == "automatic"
      assert event.actor == "scheduler"
    end

    test "accepts keyword tags" do
      assert :ok = Events.emit("health.info", %{}, tags: [source: "manual", check: "health"])

      event = Repo.one(from e in Event, order_by: [desc: e.inserted_at], limit: 1)

      assert event.tags == %{"source" => "manual", "check" => "health"}
      assert event.source == "manual"
    end

    test "returns :ok when persistence fails" do
      fixed_id = Ecto.UUID.generate()

      assert :ok = Events.emit("health.info", %{}, id: fixed_id)
      assert :ok = Events.emit("health.info", %{}, id: fixed_id)

      assert Repo.aggregate(from(e in Event, where: e.id == ^fixed_id), :count) == 1
    end

    test "emits telemetry for persisted and failed writes" do
      handler_id = "events-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:service_hub, :notifications, :event, :persisted],
            [:service_hub, :notifications, :event, :persist_failed]
          ],
          fn event, measurements, metadata, pid ->
            send(pid, {:telemetry_event, event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      fixed_id = Ecto.UUID.generate()
      assert :ok = Events.emit("health.info", %{}, id: fixed_id, tags: %{"source" => "automatic"})

      assert_receive {:telemetry_event, [:service_hub, :notifications, :event, :persisted],
                      %{count: 1}, %{event_name: "health.info", source: "automatic"}}

      assert :ok = Events.emit("health.info", %{}, id: fixed_id, tags: %{"source" => "automatic"})

      assert_receive {:telemetry_event, [:service_hub, :notifications, :event, :persist_failed],
                      %{count: 1}, %{event_name: "health.info", source: "automatic", reason: _}}
    end
  end

  describe "prune_old_events/1" do
    test "deletes events older than retention window" do
      old_ts = DateTime.add(DateTime.utc_now(), -91 * 24 * 60 * 60, :second)
      recent_ts = DateTime.add(DateTime.utc_now(), -5 * 24 * 60 * 60, :second)

      Repo.insert!(%Event{id: Ecto.UUID.generate(), name: "old.event", inserted_at: old_ts})

      recent =
        Repo.insert!(%Event{
          id: Ecto.UUID.generate(),
          name: "recent.event",
          inserted_at: recent_ts
        })

      assert Events.prune_old_events(90) == 1
      assert Repo.get(Event, recent.id)
    end
  end
end
