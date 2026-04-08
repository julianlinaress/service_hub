defmodule ServiceHub.Workers.RetentionCleanerWorker do
  @moduledoc """
  Oban cron worker for pruning old automation_runs and notification_events.

  Runs hourly via Oban Cron plugin. Replaces the custom RetentionCleaner
  automation that used a dummy automation_target.

  Retention policy:
  - automation_runs: keeps last 50 per target OR runs from last 30 days
  - notification_events: keeps events from last 90 days
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger
  alias ServiceHub.Notifications.Events
  alias ServiceHub.Repo

  @impl Oban.Worker
  def perform(_job) do
    runs_count = prune_automation_runs()
    events_count = Events.prune_old_events(90)

    if runs_count > 0 do
      Logger.info("Retention cleaner deleted #{runs_count} old automation_runs records")
    end

    if events_count > 0 do
      Logger.info("Retention cleaner deleted #{events_count} old notification_events records")
    end

    :ok
  end

  defp prune_automation_runs do
    query = """
    DELETE FROM automation_runs
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY automation_id, target_type, target_id
                 ORDER BY inserted_at DESC
               ) as rn,
               inserted_at
        FROM automation_runs
      ) ranked
      WHERE rn > 50 AND inserted_at < now() - interval '30 days'
    )
    """

    case Repo.query(query, []) do
      {:ok, %{num_rows: count}} ->
        count

      {:error, error} ->
        Logger.error("Retention cleaner failed to prune automation_runs: #{inspect(error)}")
        0
    end
  end
end
