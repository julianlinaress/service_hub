# Notification Delivery Extraction Plan

## Goal

Extract provider delivery transport into a new Go service named `service_hub_notifier`, while keeping Phoenix + Oban as source of truth for business logic and orchestration.

## Current Notification Audit

### Current flow (health/version checks)

1. `ServiceHub.Workers.HealthCheckWorker` / `ServiceHub.Workers.VersionCheckWorker` run checks.
2. `ServiceHub.Checks.NotificationTrigger` decides whether to notify.
3. `ServiceHub.Notifications.Events.emit/3` persists a record in `notification_events`.
4. `ServiceHub.Checks.NotificationTrigger` enqueues `ServiceHub.Workers.NotificationWorker`.
5. `ServiceHub.Workers.NotificationWorker` calls `ServiceHub.Notifications.EventHandler.handle_event/1`.
6. `ServiceHub.Notifications.EventHandler` resolves rules/channels and sends directly via `Req.post/2` to Telegram/Slack.

### Notification-related modules

- Context and config:
  - `lib/service_hub/notifications.ex`
  - `lib/service_hub/checks/notification_trigger.ex`
- Persistence models:
  - `lib/service_hub/notifications/event.ex` (`notification_events`)
  - `lib/service_hub/notifications/deployment_notification_state.ex` (`deployment_notification_states`)
  - `lib/service_hub/notifications/notification_channel.ex` (`notification_channels`)
  - `lib/service_hub/notifications/service_notification_rule.ex` (`service_notification_rules`)
  - `lib/service_hub/notifications/telegram_account.ex` (`notification_telegram_accounts`)
  - `lib/service_hub/notifications/telegram_destination.ex` (`notification_telegram_destinations`)
- Event persistence:
  - `lib/service_hub/notifications/events.ex`
- Delivery worker/path:
  - `lib/service_hub/workers/notification_worker.ex`
  - `lib/service_hub/notifications/event_handler.ex`
- Provider helpers:
  - `lib/service_hub/notifications/telegram.ex` (currently used for account validation and destination discovery)

### Existing bypasses and risks

- LiveView bypass exists:
  - `lib/service_hub_web/live/notification_live/index.ex` calls:
    - `ServiceHub.Notifications.EventHandler.send_telegram/7`
    - `ServiceHub.Notifications.EventHandler.send_slack/7`
  - This path sends provider traffic directly from LiveView (outside Oban).
- Delivery result persistence is weak:
  - No active, first-class delivery attempt table currently in use.
  - Retry/disposition data is not normalized per attempt.
- `ServiceHub.Notifications.EventHandler` mixes concerns:
  - Rule resolution, formatting, provider transport, and channel error updates in one module.

### Historical/dead schema artifacts

- Migrations create then drop legacy tables:
  - `notification_deliveries`, `notification_outbox`, `notification_states` were created and later removed by:
    - `priv/repo/migrations/20260106032855_drop_custom_notification_tables.exs`
- There is no active schema module backed by those dropped tables.

## Target Architecture (Phoenix + Go)

### Phoenix responsibilities

- Event creation/persistence (`notification_events`)
- Service/channel/rule resolution
- Delivery attempt persistence and state transitions
- Oban enqueue/retry orchestration
- UI/auth/settings/onboarding (including Telegram account/destination discovery)

### Go (`service_hub_notifier`) responsibilities

- Telegram transport send
- Slack transport send
- Provider-specific HTTP details and normalization
- Normalized delivery response payloads

## Incremental Refactor Plan

1. Enforce Oban-only execution for all real sends
   - Remove direct LiveView send path.
   - Ensure test sends are also enqueued as Oban jobs.
2. Introduce delivery attempt persistence model
   - Add `notification_delivery_attempts` table + Ecto schema.
   - Capture snapshots, status, provider response, and timing fields.
3. Add notifier client boundary in Phoenix
   - Introduce `ServiceHub.Notifications.NotifierClient` behavior.
   - Add HTTP implementation with configurable base URL + timeout.
4. Add Go notifier scaffold under `services/notifier`
   - Service name and docs: `service_hub_notifier`.
   - Endpoint: `POST /api/v1/deliveries`.
   - Telegram + Slack adapters with normalized responses.
5. Wire Oban worker to delivery attempts + notifier client
   - New dedicated delivery worker loads attempt, checks preconditions, calls client, persists results.
   - Retry only retryable failures.
6. Remove legacy direct provider delivery code in Phoenix
   - Remove direct Telegram/Slack send implementation from Phoenix.
   - Keep only onboarding/discovery helpers still needed by Phoenix.
7. Update docs
   - Refresh README + PROJECT_PLAN architecture and config sections.

## Commit Plan

1. `docs: audit current notification flow and define extraction plan`
2. `refactor: enforce Oban-only notification delivery orchestration`
3. `feat: add delivery attempt model and persistence updates`
4. `feat: add notifier client boundary in Phoenix`
5. `feat: add Go notifier scaffold under services/notifier`
6. `feat: wire Oban delivery worker to Go notifier service`
7. `refactor: remove legacy direct Telegram/Slack delivery code`
8. `docs: update README and project plan for notifier extraction`
