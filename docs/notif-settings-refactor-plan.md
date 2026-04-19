# Notification & Settings Refactor Plan

## Vision

Service Hub owns a single Telegram bot (configured once via environment variables).
Users connect their personal Telegram account through the Telegram Login Widget — one
click, no token copying, no chat ID hunting. The existing per-user bot token model is
removed entirely.

The user settings page becomes the central place to manage account connections
(GitHub, Telegram) alongside existing email/password settings.

---

## Telegram Connection Model

Service Hub has one Telegram bot token stored in application config (env var
TELEGRAM_BOT_TOKEN). This bot is used for all outbound notifications to all users.

When a user connects Telegram, they go through the Telegram Login Widget flow. The
widget returns a verified payload containing the user's Telegram ID, first name,
last name, and username. This is stored as a single connection per user. Only one
Telegram connection per user is allowed. The Telegram user ID is all that is needed
to send them a direct message via the platform bot.

---

## Data Model Changes

Remove entirely:
- notification_telegram_accounts table and schema (per-user bot tokens, gone)
- notification_telegram_destinations table and schema (discovered chats, gone)
- telegram_account_id and telegram_destination_id columns from notification_channels

Add:
- user_telegram_connections table with fields:
  - user_id (FK to users, unique — one connection per user)
  - telegram_id (string, the user's Telegram numeric ID)
  - first_name (string)
  - last_name (string, nullable)
  - username (string, nullable)
  - connected_at (utc_datetime)
  - timestamps

The notification_channels table stays but is simplified. For Telegram channels,
the config map only needs to know the channel belongs to the owner user — the
destination is resolved at send time by looking up the user's telegram_connection.
The token is resolved from application config, not from user data.

Service notification rules stay exactly as they are — per-service, per-channel,
with the existing rules map controlling which event types trigger notifications.

---

## Settings Page Restructure

The existing /users/settings page gains a new "Connections" section below the
existing email and password sections.

GitHub Connection subsection:
- Shows current connection status (connected/not connected)
- If connected: shows the connected scope, a "Reconnect" button, and a
  "Disconnect" button
- If not connected: shows a brief explanation ("Used for importing repositories
  from GitHub") and a "Connect GitHub" button that starts the existing OAuth flow
- Disconnecting GitHub does not affect existing providers but shows a warning
  explaining that providers using this connection may stop working

Telegram Connection subsection:
- Shows current connection status (connected/not connected)
- If connected: shows the Telegram username or first name, a "Send test message"
  button that sends a test notification to their Telegram via the platform bot,
  and a "Disconnect" button
- If not connected: shows a brief explanation ("Used to receive health and version
  alert notifications") and a "Connect Telegram" button that initiates the
  Telegram Login Widget flow
- Disconnecting Telegram shows a warning: "This will disable all Telegram
  notification channels you have configured. Your rules will be preserved but
  no messages will be sent until you reconnect."
- Disconnecting does not delete notification rules or channels, but effectively
  makes Telegram delivery fail silently until reconnected (the worker should
  handle a missing connection gracefully and skip delivery rather than error)

---

## Telegram Login Widget Flow

The Telegram Login Widget is a JavaScript widget embedded on the settings page.
It opens a Telegram authorization popup. On success, Telegram redirects or calls
a callback with a signed payload. Service Hub verifies the payload signature using
HMAC-SHA256 with the bot token as the key (this is Telegram's standard verification
method). On verification success, the user_telegram_connection record is created or
updated.

This requires:
- TELEGRAM_BOT_TOKEN in application config
- TELEGRAM_BOT_USERNAME in application config (needed for the widget initialization)
- A controller or LiveView endpoint to receive and verify the widget callback
- The settings page must be served over HTTPS in production (Telegram requirement)
  which is already handled by the existing force_ssl config

---

## Notification Channel Simplification

The existing Telegram channel creation form (currently asking for bot token and
chat reference) is replaced. Creating a Telegram channel now only requires:
- A name for the channel
- The user must have an active Telegram connection (if not, show a prompt to
  connect first on the settings page)

The channel implicitly uses the connected user's Telegram ID as the destination
and the platform bot token from config. No manual credential entry.

The channel list page should show a warning banner if the user has Telegram
channels but no active Telegram connection.

---

## Notification Delivery Changes

The NotificationDeliveryWorker, when processing a Telegram delivery attempt,
resolves the destination as follows:
- Load the channel's owner user
- Look up that user's user_telegram_connection
- If no connection exists, mark the attempt as failed with error code
  "telegram_not_connected" and do not retry (non-retryable)
- If connection exists, use the telegram_id as the chat ID and the platform
  bot token from config to call the notifier service

---

## What Does Not Change

- Service notification rules structure and UI
- Per-service control over which event types trigger notifications
- The notifier microservice interface (it still receives a destination and a token,
  just now those always come from the platform config and user connection)
- Slack channel model (not implemented yet, leave as is)
- The notification events and delivery attempts persistence
