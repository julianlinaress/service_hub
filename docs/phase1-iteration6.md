# Phase 1 – Iteration 6 Plan: Deployments & Checks

- **Scope:** Finish the Phase 1 deployment story by replacing Clients/ServiceClients with Deployments, adding deployment CRUD, and delivering manual version/health checks from the UI.
- **Goal:** Let users define deployments per service, see their status in the service detail view, and trigger checks on demand.

## Objectives & Deliverables
- Deployment domain: `deployments` table and `ServiceHub.Deployments` context with scoped CRUD, validations (host/env/name uniqueness per service), and audit timestamp updates.
- Data migration: optional conversion script/path from `clients` + `service_clients` to deployments; mark legacy contexts as deprecated but keep code until a later cleanup.
- Service detail UI: deployments list with version/health badges, add/edit form, and detail view under `/providers/:provider_id/services/:service_id/deployments/:id`.
- Manual checks: `ServiceHub.Checks.Version` and `ServiceHub.Checks.Health` modules with HTTP calls using service templates, headers for `api_key`, and auditing of results.
- Actions from UI: buttons to trigger version/health checks per deployment and bulk for a service (sequential, no background jobs yet).
- Dashboard touch-up: surface deployment counts and health summary on main/provider dashboards using existing status components.

## Non-Goals (keep iteration tight)
- No external schedulers (Quantum/Oban); use the built-in GenServer scheduler.
- No realtime UI polling from the server; countdowns are client-side and only refresh on broadcast or page load.
- No RBAC or per-user filtering changes beyond existing scope helpers.
- No pipeline/workflow orchestration; deployment is host metadata + checks only.

## Automatic Checks Implementation
**Status:** Implemented with background scheduling, audits, and client-side countdowns.

**What's Ready:**
- Database fields: `automatic_checks_enabled` (boolean), `check_interval_minutes` (integer)
- Form controls: checkbox toggle + select with intervals (1m to 24h)
- Validation: ensures interval is set when automatic checks enabled
- UI indicator: badge showing "Auto Xm/Xh" on deployment cards
- Client-side countdown hook for "Next check" (no server polling)

**What's Done:**
- GenServer scheduler (`ServiceHub.Automations.Scheduler`) with DB-locked claims
- Automation runner with timeouts, backoff, audit writes, and PubSub updates
- Target sync on deployment create/update/delete
- UTC-normalized scheduling in SQL to avoid DB timezone drift
- `next_run_at` reset on interval change or re-enable

**Automation plan (scalable pattern, fixes picked, full detail):**

### Interfaces
- **Behavior:** `ServiceHub.Automations.Behaviour`
  - `id/0` - returns automation identifier string (e.g., `"deployment_health"`)
  - `targets_query/0` - returns Ecto query for eligible targets (includes scoping, custom filters)
  - `run/1` - executes automation for an `AutomationTarget` struct
  - `timeout_seconds/0` - optional, defaults to 30s
  - `max_failures/0` - optional, defaults to 5 (before auto-pause)
  - `backoff_curve/0` - optional, returns `{base_minutes, multiplier, cap_minutes}`, defaults to `{2, 2, 120}`

### Data Model
Use dedicated schedule/state tables to avoid field collisions when multiple automations target the same record.

**`automation_targets` table:**
- `id` (primary key)
- `automation_id` (string, e.g., `deployment_health`, `deployment_version`)
- `target_type` (string, e.g., `deployment`)
- `target_id` (uuid/int, references the actual record)
- `enabled` (boolean, default true)
- `interval_minutes` (integer, required when enabled)
- `next_run_at` (utc_datetime_usec, when to run next)
- `running_at` (utc_datetime_usec, lease marker - set when claimed, cleared on complete)
- `last_started_at` (utc_datetime_usec, audit - when task actually began)
- `last_finished_at` (utc_datetime_usec, when task completed)
- `paused_at` (utc_datetime_usec, set when auto-paused due to failures)
- `last_status` (string: `ok`, `warning`, `error`, `timeout`, `stale`)
- `last_error` (text, error message from last failure)
- `consecutive_failures` (integer, default 0, resets on success)
- `lock_version` (integer, default 1, for optimistic locking if needed)
- `inserted_at`, `updated_at` (standard timestamps)
- **Unique index:** `(automation_id, target_type, target_id)`
- **Indexes:** `(next_run_at)`, `(automation_id, enabled, paused_at, next_run_at)`

**`automation_runs` table (audit log):**
- `id` (primary key)
- `automation_id` (string)
- `target_type` (string)
- `target_id` (uuid/int)
- `status` (string: `ok`, `warning`, `error`, `timeout`, `stale`)
- `started_at` (utc_datetime_usec)
- `finished_at` (utc_datetime_usec)
- `duration_ms` (integer)
- `summary` (text, brief result description)
- `error` (text, full error if failed)
- `attempt` (integer, which attempt number this was)
- `node` (string, which Erlang node ran this)
- `inserted_at` (standard timestamp)
- **Indexes:** `(automation_id, target_type, target_id, inserted_at)`, `(inserted_at)`

### Scheduler Architecture
**`ServiceHub.Automations.Scheduler` GenServer** - one per node:
- Polls database every `poll_interval_ms` (default 10s + jitter up to 10s to reduce thundering herd)
- For each registered automation (via `Application` config or Registry):
  1. Call automation's `targets_query/0` to get eligible targets
  2. Claim due targets using atomic UPDATE (see SQL below)
  3. Pass claimed targets to `Runner` for async execution
- **Cluster-safe:** Each node runs independently; coordination via DB locks (`FOR UPDATE SKIP LOCKED`)
- **Crash recovery:** If Scheduler crashes after claim but before spawning task, lease TTL ensures eventual reclaim

**`ServiceHub.Automations.Runner` module:**
- Executes tasks under `Task.Supervisor` with concurrency limits
- **Concurrency:** Global limit per node (default 10), configurable per automation type via `concurrency_limit/0` callback
- Wraps execution with timeout from automation's `timeout_seconds/0`
- Updates `automation_targets` state on completion
- Inserts `automation_runs` record for audit
- **Crash handling:** Task crashes are caught; target state updated with error; lease cleared

### Claim Algorithm (Atomic, Postgres)
The Scheduler uses the automation's `targets_query/0` as a CTE to ensure scoping doesn't drift:

```sql
WITH eligible AS (
  -- Automation's custom query injected here
  -- Example: SELECT id FROM deployments WHERE automatic_checks_enabled = true AND deleted_at IS NULL
  $1
),
due AS (
  SELECT at.id, at.interval_minutes
  FROM automation_targets at
  INNER JOIN eligible e ON e.id = at.target_id
  WHERE at.automation_id = $2
    AND at.target_type = $3
    AND at.enabled = true
    AND at.paused_at IS NULL
    AND (at.next_run_at IS NULL OR at.next_run_at <= timezone('UTC', now()))
    AND (at.running_at IS NULL OR at.running_at < timezone('UTC', now()) - $4::interval)  -- lease expired
  ORDER BY at.next_run_at NULLS FIRST, at.id
  FOR UPDATE OF at SKIP LOCKED
  LIMIT $5
)
UPDATE automation_targets at
SET running_at = timezone('UTC', now()),
    last_started_at = timezone('UTC', now()),
    next_run_at = timezone('UTC', now()) + make_interval(mins => due.interval_minutes),  -- default schedule
    updated_at = timezone('UTC', now())
FROM due
WHERE at.id = due.id
RETURNING at.*;
```

**Parameters:**
- `$1`: Automation's `targets_query/0` as prepared subquery
- `$2`: `automation_id`
- `$3`: `target_type`
- `$4`: Lease TTL interval (e.g., `'10 minutes'`)
- `$5`: Batch size (default 50)

**Lease TTL calculation:** `max(interval_minutes * 2, 10 minutes)` per target.

### State Transitions & Updates

**1. On Successful Completion:**
```sql
UPDATE automation_targets
SET running_at = NULL,
    last_finished_at = now(),
    last_status = $1,  -- 'ok' or 'warning'
    last_error = NULL,
    consecutive_failures = 0,
    updated_at = now()
WHERE id = $2;
```

**2. On Failure:**
```sql
UPDATE automation_targets
SET running_at = NULL,
    last_finished_at = now(),
    last_status = 'error',
    last_error = $1,
    consecutive_failures = consecutive_failures + 1,
    next_run_at = now() + $2::interval,  -- backoff interval
    paused_at = CASE
      WHEN consecutive_failures + 1 >= $3 THEN now()  -- max_failures threshold
      ELSE NULL
    END,
    updated_at = now()
WHERE id = $4;
```

**Backoff formula:** `min(base_minutes * multiplier^failures, cap_minutes)`
- Default: `{2, 2, 120}` → 2m, 4m, 8m, 16m, 32m, 64m, 120m (cap)

**3. On Timeout:**
Same as failure but `last_status = 'timeout'`.

**4. On Stale Lease Detection:**
When claiming finds `running_at` is expired:
- Insert `automation_runs` record with `status = 'stale'`, `finished_at = now()`, `error = "Lease expired"`
- Then proceed with claim (UPDATE sets new `running_at`)

**5. Manual Resume (UI/API action):**
```sql
UPDATE automation_targets
SET paused_at = NULL,
    consecutive_failures = 0,
    next_run_at = now(),  -- run immediately
    updated_at = now()
WHERE id = $1;
```

### Cleanup & Retention

**Deployment deletion cascades:**
```elixir
# In ServiceHub.Deployments.delete_deployment/2
def delete_deployment(scope, deployment) do
  Repo.transaction(fn ->
    # Delete automation targets first
    Automations.delete_targets_for(deployment)
    # Then delete deployment
    Repo.delete!(deployment)
  end)
end
```

**Prune old automation_runs:**
- Add `Automations.RetentionCleaner` automation (runs hourly)
- Deletes runs older than 30 days OR keeps last 50 per target (whichever is more permissive)
```sql
DELETE FROM automation_runs
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY automation_id, target_type, target_id ORDER BY inserted_at DESC) as rn,
           inserted_at
    FROM automation_runs
  ) ranked
  WHERE rn > 50 OR inserted_at < now() - interval '30 days'
);
```

### Configuration

**Application config** (`config/config.exs`):
```elixir
config :service_hub, ServiceHub.Automations.Scheduler,
  poll_interval_ms: 30_000,
  poll_jitter_ms: 10_000,  # random 0-10s added to poll interval
  batch_size: 50,
  global_concurrency: 10,
  lease_ttl_min_minutes: 10,
  lease_ttl_multiplier: 2

config :service_hub, ServiceHub.Automations,
  automations: [
    ServiceHub.Automations.HealthCheck,
    ServiceHub.Automations.VersionCheck,
    ServiceHub.Automations.RetentionCleaner
  ]
```

**Per-automation overrides** (via callbacks):
```elixir
defmodule ServiceHub.Automations.HealthCheck do
  @behaviour ServiceHub.Automations.Behaviour

  def id, do: "deployment_health"
  def timeout_seconds, do: 15
  def max_failures, do: 3
  def concurrency_limit, do: 20  # health checks can run more concurrently
  # ... other callbacks
end
```

### Logging Requirements

**Critical events (Logger.error or Logger.warning):**
- Claim query failures (DB errors)
- Task supervisor crashes
- Automation crashes/exceptions (log full stacktrace)
- Lease TTL expirations detected (warning, includes which target)
- Auto-pause triggered (warning, includes target + failure count)
- Stale run detection (warning)
- Retention pruning failures

**Standard events (Logger.info):**
- Scheduler poll cycle start (with count of due targets per automation)
- Successful run completion (compact: `automation_id`, `target_id`, `duration_ms`, `status`)
- Manual resume actions (from UI)
- Concurrency limit reached (throttling)

**Debug events (Logger.debug):**
- Claim query execution (with row count returned)
- Task spawned (with timeout and target details)
- Backoff calculations (next_run_at computed)
- Retention pruning (rows deleted count)

**Log format for successful checks:**
```
[info] Automation completed: automation=deployment_health target=deployment:123 duration=245ms status=ok
```

**Log format for failures:**
```
[error] Automation failed: automation=deployment_health target=deployment:123 duration=1250ms status=error consecutive_failures=2 next_run_at=2026-01-04T12:34:56Z error="Connection refused"
```

### Implementation for Health/Version Checks

**Today's work:**
1. Implement `ServiceHub.Automations.Behaviour`
2. Add `ServiceHub.Automations.Scheduler` GenServer
3. Add `ServiceHub.Automations.Runner` module
4. Create migrations for `automation_targets` and `automation_runs` tables
5. Implement `ServiceHub.Automations.HealthCheck` wrapping `ServiceHub.Checks.Health`
6. Implement `ServiceHub.Automations.VersionCheck` wrapping `ServiceHub.Checks.Version`
7. Implement `ServiceHub.Automations.RetentionCleaner` for pruning
8. Add `sync_automation_targets/1` to `ServiceHub.Deployments` context:
   - Called on deployment create/update/delete
   - Upserts `automation_targets` rows for `deployment_health` (if `automatic_checks_enabled`)
   - Upserts `automation_targets` rows for `deployment_version` (if `automatic_checks_enabled` AND version checks enabled for deployment)
   - Deletes `automation_targets` on deployment delete
9. Add backfill migration to sync existing deployments
10. Wire Scheduler into application supervision tree

**Upgrade path:** Keep Scheduler generic so we can later swap Runner's `Task.Supervisor` for Oban/Quantum without changing automation module code.

## Work Breakdown
1) **Schema & Migration** — Done
   - Deployments table added; backfill path from clients/service_clients included.
   - Service endpoint templates restored (version/health with `{{host}}`); deployment endpoints removed.
   - Automatic checks fields added: `automatic_checks_enabled` (boolean) and `check_interval_minutes` (integer).
2) **Context Layer** — Done
   - `ServiceHub.Deployments` with scoped CRUD, validations (host/env/name uniques per service).
   - Validation for automatic checks: interval required when enabled, must be one of allowed values.
3) **Check Engines** — Done
   - `ServiceHub.Checks.Version/Health` use service templates + deployment host, include API key, update timestamps/fields, and log URL/status/results.
4) **LiveView & Routes** — Done
   - Deployment modal inside service dashboard for add/edit; health/version triggers per deployment; settings modal for services.
   - Deployment form includes automatic checks toggle and interval selector (1m, 2m, 5m, 10m, 30m, 1h, 2h, 6h, 12h, 24h).
5) **Service Detail Integration** — Done
   - Deployments listed with health badge (color-coded: success/warning/error), version display, and actions.
   - Service endpoints removed from main view (config templates not prominent).
   - Repository info condensed to horizontal layout; deployments are primary focus.
   - Automatic checks indicator shown with badge (clock icon + interval) when enabled.
   - Manual check buttons run asynchronously with loading states (spinning icon + disabled).
   - Last checked timestamps displayed with relative time formatting.
6) **Automatic Checks Implementation**
   - Scheduler and runner implemented with DB-locked claims, timeouts, backoff, and audit logging.
   - UTC-normalized scheduling fixes DB timezone drift; `next_run_at` resets on interval change/re-enable.
   - Client-side countdown hook updates every second without server polling.
7) **Cleanup & Compatibility**
   - Legacy Clients/ServiceClients remain documented as deprecated; follow-up cleanup later.

## Risks & Decisions to Lock
- HTTP client behavior (timeouts, SSL errors) should return meaningful UI messages; default timeouts to avoid hanging LiveViews.
- Template interpolation: assume simple `{{host}}` replacement; explicitly strip protocol from host if users include it?
- Backfill strategy: only run when legacy tables exist; otherwise skip without failing.

### Newly agreed behaviors
- Health checks are mandatory for every deployment but expectation rules are configurable (e.g., require 200-only or a specific JSON shape).
- Version checks are optional per deployment; when enabled they can carry per-deployment expectations for parsing/validation.
- Health expectation shape: allowed statuses list plus optional expected JSON fragment; status outside expectations downgrades health from ok.
- Version expectation shape: optional allowed statuses list and a field name to read from JSON (plain text still works); failures record the check but don't block other actions.
- Service UX: clicking a service opens its dashboard; settings live under a separate button (no direct edit from the list).
- Service dashboards show deployments with manual health/version triggers; add/create flows will come after the dashboard wiring.
- Creating a deployment only records metadata/expectations; it does not install or deploy code.
- Endpoints remain defined at the service level (version/health templates with `{{host}}` placeholder); deployments carry the host (and optional API key) only.
- Logging: health/version checks log requested URL, status, parsing field expectations, and parsed values (or missing/empty cases) for visibility.
- Automatic checks are optional per deployment; when enabled, user selects interval from predefined options (1-1440 minutes).
- Service detail page emphasizes deployments as primary content with color-coded health badges (green/yellow/red) and relative timestamps.
- Manual check buttons show async loading states (spinning icon + "Checking..." + disabled) to provide immediate visual feedback.
- Deployment cards display automatic check status with info badge when enabled, showing interval in compact format (e.g., "Auto 5m", "Auto 2h").

## Testing Plan
- ExUnit coverage for context changesets/queries and check modules (ok/warning/down/error cases; JSON vs plain text versions).
- LiveView tests for deployment CRUD and manual triggers (button events update assigns and flash messages).
- Automation target sync tests cover interval changes, re-enable behavior, and next_run_at resets.
- Smoke test dashboard metrics to ensure queries respect user scoping.
