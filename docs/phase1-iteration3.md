# Phase 1 – Iteration 3 Snapshot

- **Scope:** Centralized OAuth connection for GitHub, reusable provider auth, and UX overhaul for provider forms.
- **New data:** `account_connections` table to store per-user OAuth credentials by provider key (token/refresh/scope/expires). Migration: `20251201000000_create_account_connections.exs`. Schema/context: `lib/service_hub/account_connections/account_connection.ex`, `lib/service_hub/account_connections.ex`.
- **OAuth central flow:** `AccountOAuthController` with `/oauth/:provider/start|callback` (GitHub implemented). Uses centralized config via `ServiceHub.OAuth.github_provider/1` (env-driven client_id/secret/base_url), and adapters’ `authorize_url`/`exchange_oauth_token`.
- **Adapters:** Behaviour gains OAuth callbacks + default scope; GitHub adapter supports OAuth tokens; Gitea returns not-supported. Adapter dispatcher accepts map/struct provider_type. Auth registry adds `github_oauth`, `oauth` entries.
- **Runtime config:** `.env` autoload via Envar (optional `ENV_FILE`), GitHub OAuth envs (`GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `GITHUB_OAUTH_BASE_URL`).
- **UI:** Provider form reorganized—GitHub now shows two clear paths: “Connect with GitHub” (applies OAuth connection and sets auth type) vs “custom auth” selector; auth select disabled until provider type chosen or when using OAuth connection. Host helper lives near base URL. Provider show uses central OAuth start. 
- **Helper APIs:** Providers `save_provider_auth_data/3`, `apply_account_connection/3` (for merge/broadcast). Live form safeguards auth_data nils.
- **Dependencies:** Added `envar` for env loading.

## Notes
- OAuth connection applies `auth_data.token/scope` and sets `auth_type` to `github_oauth` when present; toggle “Cancel use” re-enables custom auth selection.
- Central OAuth flow mirrors Vercel-style personal connection for repos; still supports PAT/GitHub App per provider.
