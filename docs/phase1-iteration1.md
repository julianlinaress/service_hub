# Phase 1 – Iteration 1 Snapshot

- **Scope:** Initial Provider management with type metadata and LiveView CRUD.
- **Data model:** Providers are scoped to a user and reference `provider_types` and `auth_types`; `auth_data` is stored as JSON with defaults; type/auth required_fields are JSON maps for dynamic inputs.
- **LiveViews:** Provider form uses select inputs for provider/auth types and renders structured fields from `required_fields`, avoiding raw JSON textareas in the UI. Index/show views display friendly summaries, not raw maps.
- **Contexts:** Providers context handles scoped CRUD, association constraints, and normalization of JSON string params; ProviderType/AuthType contexts include unique `key` per user and required_fields normalization.
- **Migrations:** Non-null constraints for core fields, default empty maps for JSON, uniqueness on `key` per user, and provider foreign keys to type tables.
- **Known gaps:** Database credentials need configuration to run tests locally; remaining Phase 1 entities (services, clients, service_clients, audit logs, health/version checks) are pending.
