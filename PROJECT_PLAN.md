# Service Hub - Project Plan

## Overview

Service Hub manages repository-backed services and their deployments across environments.
It provides provider connectivity, deployment checks, automations, and notification routing in one app.

## Current Product Status

### Implemented

- Provider management (GitHub/Gitea) with credential validation
- Service management linked to providers
- Deployment model (host/env scoped instances per service)
- Manual checks (health/version)
- Oban-based background jobs for periodic health/version checks, async notification delivery, and retention cleanup
- Notification channels and per-service notification rules
- Notification event persistence + retention cleanup
- Telegram + Slack delivery
- Telegram account/destination model with destination discovery

### In Progress

- UX hardening for notification onboarding and rule editing
- Documentation consolidation for public consumption

### Planned Next

- Telegram `/link <code>` verification handshake
- Optional encrypted storage for external credentials
- Monitoring page for event and delivery history
- Additional providers and workflow/pipeline support

## Core Domain Model

- `providers`: external source control providers
- `services`: repositories tracked in Service Hub
- `deployments`: running installations of a service
- `automation_targets` / `automation_runs`: per-deployment scheduling state and run history (driven by Oban workers)
- `oban_jobs`: background job queue (health/version checks, notifications, retention)
- `notification_channels`: delivery channels
- `service_notification_rules`: routing config by service
- `notification_events`: internal event log
- `notification_telegram_accounts`: reusable Telegram bot credentials
- `notification_telegram_destinations`: discovered Telegram chats/channels

## Notifications Direction

The notification architecture is moving to a reusable account + destination pattern:

- keep bot credentials once per user/account
- discover and store destinations separately
- let channels and rules reference destinations without manual ID hunting

This keeps Telegram onboarding safer and prepares the same shape for future providers.

## Engineering Priorities

1. Keep check and notification flows reliable and observable
2. Improve UX for setup and troubleshooting
3. Maintain clean migration paths for schema evolution
4. Preserve test coverage around automations and notifications

## Delivery Standards

- Run `mix precommit` before merging
- Keep migrations reversible when practical
- Update docs with any behavior changes that affect users
