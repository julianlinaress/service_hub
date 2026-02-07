# Service Hub

Service Hub is a Phoenix app for managing self-hosted deployments backed by Git providers.
It centralizes provider connectivity, service metadata, deployment checks, and notification routing.

## Highlights

- Provider integrations for GitHub and Gitea
- Service and deployment management per user scope
- Manual and scheduled health/version checks
- Notification rules by service and severity
- Telegram and Slack channel delivery
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

Notification channels are user-owned and support provider-specific delivery.

For Telegram, the app now separates:

- bot credentials (`notification_telegram_accounts`)
- message destinations (`notification_telegram_destinations`)
- channel routing (`notification_channels` + service rules)

This avoids copy-pasting raw `chat_id` values and supports destination discovery from Telegram updates.

## Quality Checks

Run the full local gate before pushing:

```bash
mix precommit
```

## Documentation

- Project roadmap and status: `PROJECT_PLAN.md`
- Iteration notes: `docs/`
- Team/agent workflow notes: `AGENTS.md`, `CLAUDE.md`
