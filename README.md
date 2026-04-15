# Service Hub

Service Hub is a Phoenix app for managing self-hosted deployments backed by Git providers.
It centralizes provider connectivity, service metadata, deployment checks, and notification routing.

## Highlights

- Provider integrations for GitHub and Gitea
- Service and deployment management per user scope
- Manual and scheduled health/version checks
- Notification rules by service and severity
- Oban-orchestrated delivery attempts with persistent status
- External notifier transport service (`service_hub_notifier`) for Telegram/Slack sends
- Internal notification event persistence with retention
- Telegram destination discovery flow (bot account + discovered chats)

## Tech Stack

- Elixir / Phoenix LiveView
- Ecto + PostgreSQL
- Req for outbound HTTP integrations
- Tailwind + DaisyUI for UI

## Quick Start

1. Install dependencies and prepare databases:

```bash
mix setup
```

2. Start the app:

```bash
mix phx.server
```

3. Open `http://localhost:4000`.

## Required Environment Variables

Service Hub loads env values using `Envar` from `.env` by default.

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `GITHUB_OAUTH_CLIENT_ID`
- `GITHUB_OAUTH_CLIENT_SECRET`

Optional runtime controls include `PORT`, `POOL_SIZE`, and `ECTO_IPV6`.

## Notifications Overview

Notification channels are user-owned and support provider-specific destinations.

Notification flow is fully orchestrated by Phoenix + Oban:

1. check/domain event occurs
2. Phoenix persists `notification_events`
3. Phoenix resolves service rules and channels
4. Phoenix persists `notification_delivery_attempts`
5. Oban enqueues and executes delivery jobs
6. worker calls `service_hub_notifier` (`POST /api/v1/deliveries`)
7. attempt status/result is persisted

Transport details are outside this repo in the separate Go repository:

- `service_hub_notifier`

Phoenix remains the source of truth for business rules, persistence, and retries.

For Telegram, the app now separates:

- bot credentials (`notification_telegram_accounts`)
- message destinations (`notification_telegram_destinations`)
- channel routing (`notification_channels` + service rules)

This avoids copy-pasting raw `chat_id` values and supports destination discovery from Telegram updates.

## Notifier Configuration

Phoenix uses these runtime settings to call `service_hub_notifier`:

- `NOTIFIER_BASE_URL` (default: `http://localhost:8081`)
- `NOTIFIER_TIMEOUT_MS` (default: `5000`)
- `NOTIFIER_INTERNAL_SERVICE_TOKEN` (required in production)

Phoenix sends:

- `Authorization: Bearer <NOTIFIER_INTERNAL_SERVICE_TOKEN>`
- `X-Request-Id` and `X-Attempt-Id` headers derived from `delivery_attempt_key`

## Production Deployment (Single VM)

Use the production compose stack:

- `docker-compose.prod.yml`

Architecture:

- `nginx` (public edge)
- `phoenix` (`service_hub`)
- `notifier` (`service_hub_notifier`, private-only)

All services run on the private bridge network `service_hub_net`.
Notifier is not exposed publicly and is reachable only through internal DNS:

- `http://notifier:8081`

1. Copy `.env.prod.example` to `.env.prod` and fill real values.
2. Export `PHOENIX_IMAGE` and `NOTIFIER_IMAGE` with immutable tags (`sha-*` or `v*`).
3. Start stack:

```bash
docker compose -f docker-compose.prod.yml up -d
```

## Quality Checks

Run the full local gate before pushing:

```bash
mix precommit
```

## Documentation

- Project roadmap and status: `PROJECT_PLAN.md`
- Iteration notes: `docs/`
- Team/agent workflow notes: `AGENTS.md`, `CLAUDE.md`
