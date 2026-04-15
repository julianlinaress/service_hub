defmodule ServiceHub.Workers.NotificationWorker do
  @moduledoc """
  Oban worker for async notification orchestration.

  Resolves channels and enqueues dedicated delivery attempt jobs.
  Actual provider delivery happens in `NotificationDeliveryWorker`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias ServiceHub.Notifications.EventHandler

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event} = args}) do
    channel_id = Map.get(args, "channel_id") || Map.get(event, "channel_id")

    opts =
      case channel_id do
        nil -> []
        value -> [only_channel_id: value]
      end

    EventHandler.enqueue_deliveries(
      %{
        id: event["id"],
        name: event["name"],
        payload: event["payload"],
        tags: event["tags"]
      },
      opts
    )

    :ok
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # 10s, 30s, 90s
    trunc(:math.pow(3, attempt) * 10)
  end
end
