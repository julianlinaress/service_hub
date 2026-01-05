defmodule ServiceHub.Automations.Scheduler do
  @moduledoc """
  GenServer that periodically polls for due automation targets and executes them.

  One Scheduler runs per node. Coordination is handled via database locks
  (FOR UPDATE SKIP LOCKED) so multiple nodes can safely poll simultaneously.

  Configuration (via Application env):
  - poll_interval_ms: Base poll interval (default 30_000)
  - poll_jitter_ms: Random jitter added to poll interval (default 10_000)
  - batch_size: Max targets to claim per automation per poll (default 50)
  - global_concurrency: Max concurrent tasks per node (default 10)
  - lease_ttl_min_minutes: Minimum lease TTL (default 10)
  - lease_ttl_multiplier: Lease TTL = max(interval * multiplier, min) (default 2)
  """
  use GenServer
  require Logger
  import Ecto.Query
  alias ServiceHub.Automations.{AutomationTarget, AutomationRun, Runner}
  alias ServiceHub.Repo

  @default_config [
    poll_interval_ms: 30_000,
    poll_jitter_ms: 10_000,
    batch_size: 50,
    global_concurrency: 10,
    lease_ttl_min_minutes: 10,
    lease_ttl_multiplier: 2
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Keyword.merge(@default_config, opts)
    automations = get_automations()
    automation_ids = Enum.map(automations, & &1.id())

    Logger.info(
      "Automation Scheduler started with #{length(automations)} automations: #{Enum.join(automation_ids, ", ")}"
    )

    Logger.info(
      "Automation Scheduler config: poll_interval_ms=#{config[:poll_interval_ms]} poll_jitter_ms=#{config[:poll_jitter_ms]} batch_size=#{config[:batch_size]} global_concurrency=#{config[:global_concurrency]} lease_ttl_min_minutes=#{config[:lease_ttl_min_minutes]} lease_ttl_multiplier=#{config[:lease_ttl_multiplier]}"
    )

    log_time_snapshot("init")

    # Schedule first poll with jitter
    schedule_poll(config)

    {:ok, %{config: config, automations: automations, running_tasks: %{}}}
  end

  @impl true
  def handle_info(:poll, state) do
    Logger.info(
      "Automation Scheduler poll cycle starting: automations=#{length(state.automations)} running_tasks=#{map_size(state.running_tasks)}"
    )

    log_time_snapshot("poll")

    # Poll each automation
    Enum.each(state.automations, fn automation_module ->
      poll_automation(automation_module, state)
    end)

    # Schedule next poll
    schedule_poll(state.config)

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, _result}, state) do
    # Task completed successfully
    {:noreply, remove_task(state, ref)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Task exited (success or failure)
    {:noreply, remove_task(state, ref)}
  end

  # Private Functions

  defp get_automations do
    Application.get_env(:service_hub, ServiceHub.Automations, [])
    |> Keyword.get(:automations, [])
  end

  defp schedule_poll(config) do
    base_interval = config[:poll_interval_ms]
    jitter_ms = config[:poll_jitter_ms]
    jitter = if jitter_ms > 0, do: :rand.uniform(jitter_ms), else: 0
    delay_ms = base_interval + jitter

    Logger.debug(
      "Automation Scheduler next poll scheduled in #{delay_ms}ms (base=#{base_interval}ms jitter=#{jitter}ms)"
    )

    Process.send_after(self(), :poll, delay_ms)
  end

  defp poll_automation(automation_module, state) do
    automation_id = automation_module.id()
    batch_size = state.config[:batch_size]
    lease_ttl = calculate_lease_ttl(state.config)
    available_slots = available_concurrency(state, automation_module)

    # Claim due targets using the atomic query
    targets = claim_due_targets(automation_module, automation_id, batch_size, lease_ttl)
    claimed_count = length(targets)

    Logger.info(
      "Automation Scheduler poll: automation=#{automation_id} claimed=#{claimed_count} available_slots=#{available_slots} batch_size=#{batch_size} lease_ttl_minutes=#{lease_ttl}"
    )

    if claimed_count > 0 do
      Logger.debug(
        "Automation Scheduler claimed #{claimed_count} due targets for automation=#{automation_id}"
      )

      targets
      |> Enum.take(available_slots)
      |> Enum.each(fn target ->
        Logger.debug(
          "Automation Scheduler scheduling target: automation=#{automation_id} target=#{target.target_type}:#{target.target_id} interval_minutes=#{target.interval_minutes} next_run_at=#{format_ts(target.next_run_at)} running_at=#{format_ts(target.running_at)}"
        )

        spawn_task(state, automation_module, target)
      end)

      if claimed_count > available_slots do
        Logger.info(
          "Automation Scheduler throttling: #{claimed_count - available_slots} targets queued for next poll"
        )
      end
    else
      log_next_run_at(automation_id)
    end
  end

  defp claim_due_targets(automation_module, automation_id, batch_size, lease_ttl_minutes) do
    # Build the eligible targets subquery
    eligible_query = automation_module.targets_query()

    # Use raw SQL for the atomic claim operation
    query = """
    WITH eligible AS (
      #{eligible_subquery_to_sql(eligible_query)}
    ),
    due AS (
      SELECT at.id, at.interval_minutes
      FROM automation_targets at
      INNER JOIN eligible e ON e.id = at.target_id
      WHERE at.automation_id = $1
        AND at.target_type = $2
        AND at.enabled = true
        AND at.paused_at IS NULL
        AND (at.next_run_at IS NULL OR at.next_run_at <= timezone('UTC', now()))
        AND (at.running_at IS NULL OR at.running_at < timezone('UTC', now()) - make_interval(mins => $3))
      ORDER BY at.next_run_at NULLS FIRST, at.id
      FOR UPDATE OF at SKIP LOCKED
      LIMIT $4
    )
    UPDATE automation_targets at
    SET running_at = timezone('UTC', now()),
        last_started_at = timezone('UTC', now()),
        next_run_at = timezone('UTC', now()) + make_interval(mins => due.interval_minutes),
        updated_at = timezone('UTC', now())
    FROM due
    WHERE at.id = due.id
    RETURNING at.*;
    """

    # Detect stale leases before claiming
    detect_stale_leases(automation_id, lease_ttl_minutes)

    # Execute the claim
    result =
      Repo.query(
        query,
        [automation_id, "deployment", lease_ttl_minutes, batch_size]
      )

    case result do
      {:ok, %{rows: rows, columns: columns}} ->
        rows
        |> Enum.map(fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
          |> atomize_keys()
          |> then(&struct(AutomationTarget, &1))
        end)

      {:error, error} ->
        Logger.error(
          "Automation Scheduler claim failed: automation=#{automation_id} error=#{inspect(error)}"
        )

        []
    end
  end

  defp eligible_subquery_to_sql(query) do
    # Convert Ecto query to SQL for use in CTE
    # For now, use a simple implementation that works for basic queries
    {sql, _params} = Repo.to_sql(:all, query)
    # Replace positional parameters with actual values (simple version)
    # In production, this would need proper parameter handling
    sql
  end

  defp detect_stale_leases(automation_id, lease_ttl_minutes) do
    # Find targets with expired leases
    query = """
    SELECT id, target_type, target_id, running_at
    FROM automation_targets
    WHERE automation_id = $1
      AND running_at IS NOT NULL
      AND running_at < timezone('UTC', now()) - make_interval(mins => $2)
    """

    case Repo.query(query, [automation_id, lease_ttl_minutes]) do
      {:ok, %{rows: [_ | _] = rows}} ->
        Enum.each(rows, fn [_id, target_type, target_id, running_at] ->
          Logger.warning(
            "Automation stale lease detected: automation=#{automation_id} target=#{target_type}:#{target_id} running_at=#{running_at}"
          )

          # Insert stale run record
          %AutomationRun{}
          |> AutomationRun.changeset(%{
            automation_id: automation_id,
            target_type: target_type,
            target_id: target_id,
            status: "stale",
            started_at: running_at,
            finished_at: DateTime.utc_now(:microsecond),
            error: "Lease expired",
            attempt: 0,
            node: "unknown"
          })
          |> Repo.insert()
        end)

      _ ->
        :ok
    end
  end

  defp calculate_lease_ttl(config) do
    # Return minutes as integer - will be converted to interval in SQL
    config[:lease_ttl_min_minutes]
  end

  defp available_concurrency(state, automation_module) do
    global_limit = state.config[:global_concurrency]
    automation_limit = ServiceHub.Automations.Behaviour.concurrency_limit(automation_module)

    current_count = map_size(state.running_tasks)

    limit = automation_limit || global_limit
    max(0, limit - current_count)
  end

  defp spawn_task(state, automation_module, target) do
    task =
      Task.Supervisor.async_nolink(
        ServiceHub.TaskSupervisor,
        fn -> Runner.execute(automation_module, target) end
      )

    Logger.debug(
      "Automation task spawned: automation=#{target.automation_id} target=#{target.target_type}:#{target.target_id} task=#{inspect(task.ref)}"
    )

    # Track the task
    put_in(state.running_tasks[task.ref], %{
      automation_id: target.automation_id,
      target_id: target.target_id
    })
  end

  defp remove_task(state, ref) do
    put_in(state.running_tasks, Map.delete(state.running_tasks, ref))
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp log_next_run_at(automation_id) do
    summary =
      from(at in AutomationTarget,
        where:
          at.automation_id == ^automation_id and at.enabled == true and
            is_nil(at.paused_at),
        select: {count(at.id), min(at.next_run_at)}
      )
      |> Repo.one()

    now = DateTime.utc_now(:second)

    case summary do
      {0, _} ->
        Logger.info(
          "Automation Scheduler idle: automation=#{automation_id} targets=0 now=#{format_ts(now)}"
        )

      {count, next_run_at} ->
        Logger.info(
          "Automation Scheduler idle: automation=#{automation_id} targets=#{count} next_run_at=#{format_ts(next_run_at)} now=#{format_ts(now)} eta_seconds=#{format_eta_seconds(next_run_at, now)}"
        )
    end
  end

  defp format_ts(nil), do: "nil"
  defp format_ts(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_ts(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_ts(other), do: to_string(other)

  defp log_time_snapshot(context) do
    app_now = DateTime.utc_now(:second)

    db_snapshot =
      Repo.query(
        "SELECT now(), now() AT TIME ZONE 'UTC', current_setting('TIMEZONE')",
        []
      )

    case db_snapshot do
      {:ok, %{rows: [[db_now, db_now_utc, db_tz]]}} ->
        drift_seconds =
          case db_now do
            %DateTime{} -> DateTime.diff(db_now, app_now, :second)
            _ -> "unknown"
          end

        Logger.info(
          "Automation Scheduler time snapshot: context=#{context} app_utc=#{format_ts(app_now)} db_now=#{format_ts(db_now)} db_utc=#{format_ts(db_now_utc)} db_tz=#{db_tz} drift_seconds=#{drift_seconds}"
        )

      {:error, error} ->
        Logger.warning(
          "Automation Scheduler time snapshot failed: context=#{context} error=#{inspect(error)}"
        )
    end
  end

  defp format_eta_seconds(nil, _now), do: "unknown"

  defp format_eta_seconds(%DateTime{} = next_run_at, %DateTime{} = now) do
    DateTime.diff(next_run_at, now, :second)
  end

  defp format_eta_seconds(%NaiveDateTime{} = next_run_at, %DateTime{} = now) do
    now_naive = DateTime.to_naive(now)
    NaiveDateTime.diff(next_run_at, now_naive, :second)
  end

  defp format_eta_seconds(_next_run_at, _now), do: "unknown"
end
