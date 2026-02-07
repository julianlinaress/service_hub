# Phase 1 – Iteration 7 Plan: Notifications (Alerts/Warnings)

- **Scope:** Add alert/warning notifications for health/version checks and automation events using the internal notification event pipeline (Telegram primary, Slack planned alongside).
- **Goal:** Provide per-service, per-alert configuration with reliable delivery, deduplication, and clear UI controls. Tests are **critical and core** for this implementation.

## Objectives & Deliverables
- Notifications context `ServiceHub.Notifications` with rules evaluation, enqueueing, delivery logging, and adapters.
- Telegram integration (full), Slack integration (ready, same flow).
- Service-level configuration to enable/disable alerts and choose which events notify.
- Per-service channel setup (Telegram/Slack) with test delivery and visible status.
- Dedupe/throttle logic to avoid spam and handle clustered nodes.
- Fully asynchronous delivery pipeline (outbox + worker) so checks never block on notifications.
- Robust failure handling and retry/backoff; audit success/error outcomes retained for a defined window.

## Non-Goals (keep iteration tight)
- No user-level RBAC changes.
- No advanced escalation policies (PagerDuty, email, SMS).
- No scheduled digests (only event-based notifications).

## Events & Severity Model
- **Health check:**
  - `warning` -> warning notification
  - `down`/`timeout`/`error` -> alert notification
  - `ok` after warning/down -> recovery (optional)
- **Version check:**
  - version change -> info/warning (configurable)
  - error/timeout/unparseable -> warning/alert (configurable)
- **Automation events:**
  - auto-paused, resume, stale lease -> warning/alert (configurable)

## Data Model (proposed)
**`notification_channels`**
- `id`
- `user_id`
- `provider` ("telegram" | "slack")
- `name`
- `config` (map, contains tokens, chat_id, webhook, etc.)
- `enabled` (boolean)
- `last_error` (text)
- `last_sent_at` (utc_datetime_usec)
- timestamps

**`notification_outbox`** (async queue)
- `id`
- `channel_id`
- `service_id`
- `deployment_id` (nullable)
- `check_type`
- `severity`
- `payload` (map, normalized message + metadata)
- `status` ("pending" | "processing" | "sent" | "failed" | "dead")
- `attempt` (integer)
- `next_run_at` (utc_datetime_usec)
- `locked_at` (utc_datetime_usec)
- `lock_owner` (string, node name)
- `last_error`
- timestamps

**`service_notification_rules`**
- `id`
- `service_id`
- `channel_id`
- `enabled` (boolean)
- `rules` (map: per-event toggles)
- `notify_on_manual` (boolean)
- `mute_until` (utc_datetime_usec, nullable)
- `reminder_interval_minutes` (integer, nullable)
- timestamps

**`notification_states`** (for dedupe/change tracking)
- `id`
- `service_id`
- `deployment_id` (nullable)
- `check_type` ("health" | "version" | "automation")
- `last_status`
- `last_version` (nullable)
- `last_notified_at`
- timestamps

**`notification_deliveries`** (audit)
- `id`
- `channel_id`
- `service_id`
- `deployment_id` (nullable)
- `check_type`
- `severity`
- `status` ("sent" | "failed")
- `dedupe_key` (unique)
- `sent_at`
- `error`
- `response`
- timestamps

## Service Configuration Examples
Example rules map per service:
```elixir
%{
  "enabled" => true,
  "health" => %{"warning" => true, "alert" => true, "recovery" => false},
  "version" => %{"change" => true, "error" => true},
  "automation" => %{"auto_paused" => true, "resumed" => false},
  "notify_on_manual" => false
}
```

## Integration Points
- **Checks:** emit events from the caller with explicit `source` (manual vs automatic) to avoid double-notify.
- **Automation Runner:** after `update_target_state/6`, emit automation-related notifications for automatic checks.
- **PubSub:** keep broadcast for UI; notifications are independent and must not rely on LiveView presence.

## Delivery Flow
1. Normalize event -> `check_type`, `severity`, `message`, `metadata`, `dedupe_key`.
2. Load service rules + channels -> filter by enabled/mute/config.
3. Dedupe with `dedupe_key` + change-only gating (scoped per channel).
4. Enqueue to `notification_outbox` (async, cluster-safe).
5. Worker claims pending items using the existing automation scheduler pattern (DB locks), sends via provider adapters.
6. Record `notification_deliveries`, update `notification_states`, and set outbox status.
7. On failure -> increment attempt, compute backoff, update channel error state.

## Failure Modes & Mitigations
- Invalid token/chat_id/webhook -> mark channel error, show in UI, avoid blocking checks.
- Rate limits/timeouts -> retry with backoff; prevent floods with throttle.
- Duplicates across nodes -> unique `dedupe_key` scoped per channel.
- Manual checks spam -> `notify_on_manual` default false.
- Service/deployment deleted during send -> safe no-op and record failure if needed.

## UI/UX Plan
- Add “Notifications” section in service settings.
- Channel management:
  - Add/edit Telegram and Slack channels
  - Enable/disable per channel
  - “Send test” action
  - Show last error + last sent timestamp
- Rules editor:
  - Health/Version/Automation toggles
  - Recovery toggles
  - Mute/snooze time
  - Manual check notify toggle

## Work Breakdown
1. **Spike adapters**: validate Telegram + Slack payloads and error behavior.
2. **Schema & Migration**: add notification tables + indexes + unique constraints.
3. **Context layer**: `ServiceHub.Notifications` with rule evaluation + dedupe.
4. **Adapters**: `ServiceHub.Notifications.Adapters.Telegram` and `.Slack` using direct API/webhook delivery.
5. **Outbox worker**: reuse the existing automation scheduler pattern (DB-locked claims + Task.Supervisor), but keep a separate Notifications namespace/modules.
6. **Integration hooks**: checks + automation runner + event normalization.
7. **UI**: service settings for channels + rules + test delivery.
8. **Logging & metrics**: failures, rate limit handling, backoff visibility.
9. **Retention**: prune old `notification_deliveries` and `notification_outbox` rows.

## Testing Plan (Critical)
Tests are **critical and core** to this iteration.
- Unit tests for rules evaluation, dedupe keys, and state transitions.
- Adapter tests with stubbed responses (success, rate limit, invalid token).
- Integration tests for check -> notification flow.
- LiveView tests for settings UI and channel management.
- Concurrency tests for dedupe across multiple nodes (unique index safety).
- Worker tests for retry/backoff and outbox claiming.

## Known Flaws & Chosen Solutions
- **Potential double-notify (manual + automatic):** emit events only at the call site with a `source` flag, and keep a single automatic emission in the runner.
- **Cross-channel suppression from dedupe/state:** scope `dedupe_key` and `notification_states` per channel to avoid one channel blocking another.
- **Blocking check flow on delivery:** async outbox with DB-locked claim; never send inline with checks.
- **Cluster duplication:** unique `dedupe_key` per channel + `FOR UPDATE SKIP LOCKED` claims.
- **Unbounded audit growth:** retention job to keep last N per service/deployment and purge older than a time window.

## Open Questions to Resolve Early
- Where to store tokens (DB `config` vs env-only)?
- How to store Telegram `chat_id` (per channel in `config`, with validation and a simple “send test” to verify)?
- Future requirement: support different Telegram bots per service. Design `notification_channels.config` to allow bot scoping, but do not implement per-service bots in this iteration.
- Default behavior for manual checks (`notify_on_manual`)?
- Should recovery notifications be enabled by default?
- Minimum throttle window to avoid alert storms?
