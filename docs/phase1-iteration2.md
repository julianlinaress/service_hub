# Phase 1 – Iteration 2 Snapshot

- **Scope:** Provider validation flow, service CRUD tied to provider repos, Gitea token helper, and global type registry cleanup.
- **Migrations:** Added clients, services, service_clients, audit_logs, provider validation fields; converted provider/auth types to global (no user_id) and relaxed provider.auth_type FK to nilify on delete.
- **Adapters/validation:** Introduced provider adapter behaviour and Gitea adapter for connection/repo checks plus PAT creation (Basic auth) with normalized/default scopes. Provider validation status stored in `last_validation_status/error/at` (timestamps truncated to seconds). Key files: `lib/service_hub/provider_adapters/behaviour.ex`, `lib/service_hub/provider_adapters/gitea.ex`, `lib/service_hub/providers.ex`.
- **Services:** Added service schema/context; repo validation always goes through the provider adapter (no provider conditionals). Files: `lib/service_hub/services.ex`, `lib/service_hub/services/service.ex`, migration `priv/repo/migrations/20251126232100_create_services.exs`.
- **Types/registry:** Auth/provider types enforced globally; auth types pull specs from registry (token auth with required `token` field). Files: `lib/service_hub/providers/auth_registry.ex`, `lib/service_hub/providers/auth_type.ex`, `lib/service_hub/providers/provider_type.ex`, migrations `20251126232500_make_types_global.exs`, `20251126232600_relax_provider_auth_fk.exs`.
- **UI:** Provider show lists services with inline new/edit/delete, exposes “Validate connection,” and includes a token helper form that saves the PAT into provider auth_data. Provider index shows validation state. Files: `lib/service_hub_web/live/provider_live/show.ex`, `lib/service_hub_web/live/service_live/form_component.ex`, `lib/service_hub_web/live/provider_live/index.ex`, routes in `lib/service_hub_web/router.ex`.
- **Defaults/assumptions:** PAT scopes default to `read:repository`, `write:repository`, `read:user`, `read:notification` if none provided. Providers can be created without an auth type; FK nullifies on auth type delete.
- **Open items:** Implement clients/service_clients + audit contexts/UI, version/health check engine, and workflow dispatch handling for later phases. Run `mix ecto.migrate` for pending migrations.

## Examples / How-tos
- Create provider type and auth type (token) using registry: ensure `auth_types` and `provider_types` have keys matching adapter (`gitea`, `token`). Form selects are driven from DB, but values are fixed by registry (`lib/service_hub_web/live/auth_type_live/form.ex` and `provider_type_live/form.ex`).
- Create provider (UI `/providers/new`): choose provider/auth types, set base URL, and paste token if already available. Validation button will call Gitea `/api/v1/user` via adapter.
- Generate token from UI: on provider show, open “Gitea token helper,” enter username/password, optional token name; app POSTs to `/api/v1/users/:username/tokens` (Basic auth) with default scopes, stores `auth_data["token"]`.
- Create service: from provider show, “New service,” enter owner/repo; adapter validates via `/api/v1/repos/:owner/:repo` before insert.
- Validation audit fields: `last_validation_status`, `last_validation_error`, `last_validated_at` (second precision) on providers; shown on index/show.
