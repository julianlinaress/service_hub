# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Service Hub is a modular deployment orchestrator built with Elixir/Phoenix that manages:
- **Providers** - External code hosting instances (Gitea, GitHub) with OAuth/PAT authentication
- **Services** - Repositories hosted on providers
- **Clients** - Customer installations
- **ServiceClients** - Specific service deployments on client VMs

All configuration is database-driven with no hardcoded provider logic.

## Common Commands

```bash
# Development
mix setup              # Install deps, create DB, run migrations, setup assets
mix phx.server         # Start Phoenix server

# Database
mix ecto.migrate       # Run migrations
mix ecto.reset         # Drop, create, migrate, seed

# Testing
mix test               # Run all tests
mix test path/to/test.exs           # Run single test file
mix test path/to/test.exs:42        # Run specific test at line

# Quality
mix format             # Format code
mix precommit          # Full check: compile (warnings-as-errors), unlock unused deps, format, test

# Assets
mix assets.build       # Compile Tailwind + esbuild
```

## Architecture

### Provider Abstraction Layer

All external provider interactions go through a behaviour-based adapter system:

- `ServiceHub.ProviderAdapters.Behaviour` - Defines the contract (validate_connection, list_repositories, etc.)
- `ServiceHub.ProviderAdapters` - Dispatcher that routes to the correct adapter based on `provider_type.key`
- `ServiceHub.ProviderAdapters.Gitea` / `.GitHub` - Concrete implementations

**No direct HTTP calls outside adapters.** Use `Req` for HTTP within adapters.

### Context Modules

Context modules follow Phoenix conventions and always take `%Scope{}` as first argument:
- `ServiceHub.Providers` - Manages providers, provider_types, auth_types
- `ServiceHub.Services` - Manages services
- `ServiceHub.Clients` - Manages clients
- `ServiceHub.ServiceClients` - Manages service deployments

Access current user via `scope.user` in queries. In templates, use `@current_scope.user`.

### Background Jobs (Oban)

All background work runs through Oban. **Do not introduce new GenServer-based pollers or `Task.Supervisor` background workers** — add Oban workers instead.

Workers live in `lib/service_hub/workers/`:

- `CheckEnqueuerWorker` — cron job (every minute) that polls `automation_targets` for due deployments and enqueues check jobs. Source of truth for "what to run when" is the `automation_targets` table (per-deployment `interval_minutes`, `next_run_at`, `consecutive_failures`, `paused_at`).
- `HealthCheckWorker` — runs one health check on the `:health_checks` queue. `max_attempts: 1` because retry/backoff is managed via `automation_targets`, not Oban retries.
- `VersionCheckWorker` — runs one version check on the `:version_checks` queue. Same retry model as HealthCheckWorker.
- `NotificationWorker` — async Telegram/Slack delivery on the `:notifications` queue with 3 Oban retries.
- `RetentionCleanerWorker` — hourly cron job on the `:maintenance` queue that prunes old `automation_runs` and `notification_events`.
- `CheckHelpers` — shared logic for updating `automation_targets` state, inserting `automation_runs` audit records, exponential backoff, and result normalization.

Queues: `default: 10`, `health_checks: 20`, `version_checks: 10`, `notifications: 5`, `maintenance: 1`.

Notification flow: `NotificationTrigger` persists the event synchronously via `Events.emit/3` (audit), then enqueues a `NotificationWorker` job for the actual HTTP delivery. Manual checks from the LiveView use the same path and also get async delivery for free.

Tests use `Oban.Testing` with `testing: :manual` (configured in `config/test.exs`). Use `perform_job/2`, `assert_enqueued/1`, `refute_enqueued/1`.

### LiveView Patterns

**Async data loading pattern:**
1. Initialize assigns with `AsyncResult.loading()`
2. Trigger work with `start_async/3`
3. Handle results in `handle_async/3` using `AsyncResult.ok/1` or `AsyncResult.failed/2`
4. Render with `<.async_result>` component slots (`:loading`, `:failed`, `:let={result}`)
5. **Always include an error clause** in `handle_async/3` for `{:exit, reason}`

### Routing & Authentication

Routes requiring auth go in the existing `live_session :require_authenticated_user` block. Public routes use `live_session :current_user`. Never duplicate live_session names.

## Frontend Guidelines

- Use daisyUI theme colors (primary, secondary, error, success, etc.) - never hardcoded Tailwind colors like `bg-blue-500`
- Create components in dedicated files, not in `core_components.ex` unless truly app-wide
- Use LiveComponents for stateful/interactive pieces

## Elixir Constraints

- **Guards cannot call remote functions** - `String.trim/1`, `String.contains?/2` etc. are NOT allowed in guards
- Use `System.get_env/2` or `Envar.get/2` with second argument for defaults, not `|| default`
