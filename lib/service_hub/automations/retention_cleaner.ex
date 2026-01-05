defmodule ServiceHub.Automations.RetentionCleaner do
  @moduledoc """
  Automation for pruning old automation_runs records.

  Retains:
  - Last 50 runs per target, OR
  - Runs from last 30 days
  (whichever is more permissive)

  Runs hourly on a single dummy target.
  """
  @behaviour ServiceHub.Automations.Behaviour

  require Logger
  alias ServiceHub.Repo

  @impl true
  def id, do: "retention_cleaner"

  @impl true
  def targets_query do
    # This automation doesn't target real records; return a static query
    # We'll use a dummy target_id of 1
    import Ecto.Query
    from f in fragment("SELECT 1 as id"), select: f.id
  end

  @impl true
  def run(_target) do
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
        if count > 0 do
          Logger.info("Retention cleaner deleted #{count} old automation_runs records")
        end

        {:ok, "Deleted #{count} old runs"}

      {:error, error} ->
        Logger.error("Retention cleaner failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def timeout_seconds, do: 60

  @impl true
  def max_failures, do: 10
end
