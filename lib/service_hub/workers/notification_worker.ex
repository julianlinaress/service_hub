defmodule ServiceHub.Workers.NotificationWorker do
  @moduledoc """
  Oban worker for async notification delivery to Telegram/Slack.

  Decouples HTTP delivery from check execution so slow API calls
  don't delay automation result recording. Failed deliveries are
  retried up to 3 times with exponential backoff.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias ServiceHub.Notifications.EventHandler

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event}}) do
    EventHandler.handle_event(%{
      name: event["name"],
      payload: event["payload"],
      tags: event["tags"]
    })

    :ok
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # 10s, 30s, 90s
    trunc(:math.pow(3, attempt) * 10)
  end
end
