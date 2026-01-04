# Phase 1 – Iteration 6 Plan: Deployments & Checks

- **Scope:** Finish the Phase 1 deployment story by replacing Clients/ServiceClients with Deployments, adding deployment CRUD, and delivering manual version/health checks from the UI.
- **Goal:** Let users define deployments per service, see their status in the service detail view, and trigger checks on demand.

## Objectives & Deliverables
- Deployment domain: `deployments` table and `ServiceHub.Deployments` context with scoped CRUD, validations (host/env/name uniqueness per service), and audit timestamp updates.
- Data migration: optional conversion script/path from `clients` + `service_clients` to deployments; mark legacy contexts as deprecated but keep code until a later cleanup.
- Service detail UI: deployments list with version/health badges, add/edit form, and detail view under `/providers/:provider_id/services/:service_id/deployments/:id`.
- Manual checks: `ServiceHub.Checks.Version` and `ServiceHub.Checks.Health` modules with HTTP calls using service templates, headers for `api_key`, and auditing of results.
- Actions from UI: buttons to trigger version/health checks per deployment and bulk for a service (sequential, no background jobs yet).
- Dashboard touch-up: surface deployment counts and health summary on main/provider dashboards using existing status components.

## Non-Goals (keep iteration tight)
- No background scheduling (Quantum/Oban) or recurring checks — UPDATED: Schema/UI ready but GenServer implementation deferred.
- No realtime PubSub updates; UI refresh relies on redirects/patches.
- No RBAC or per-user filtering changes beyond existing scope helpers.
- No pipeline/workflow orchestration; deployment is host metadata + checks only.

## Future Work: Automatic Checks Implementation
**Status:** Schema and UI complete; scheduler not yet implemented.

**What's Ready:**
- Database fields: `automatic_checks_enabled` (boolean), `check_interval_minutes` (integer)
- Form controls: checkbox toggle + select with intervals (1m to 24h)
- Validation: ensures interval is set when automatic checks enabled
- UI indicator: badge showing "Auto Xm/Xh" on deployment cards

**What's Needed:**
- GenServer to manage check scheduling per deployment
- Query deployments where `automatic_checks_enabled = true`
- Schedule checks based on `check_interval_minutes`
- Handle process supervision and error recovery
- Consider: single scheduler vs per-deployment processes
- Consider: Oban/Quantum integration vs custom GenServer
- Ensure checks don't overlap (track last run, skip if still running)
- Respect user scope (don't run checks for deleted/disabled deployments)

## Work Breakdown
1) **Schema & Migration** — Done
   - Deployments table added; backfill path from clients/service_clients included.
   - Service endpoint templates restored (version/health with `{{host}}`); deployment endpoints removed.
   - Automatic checks fields added: `automatic_checks_enabled` (boolean) and `check_interval_minutes` (integer).
2) **Context Layer** — Done
   - `ServiceHub.Deployments` with scoped CRUD, validations (host/env/name uniques per service).
   - Validation for automatic checks: interval required when enabled, must be one of allowed values.
3) **Check Engines** — Done
   - `ServiceHub.Checks.Version/Health` use service templates + deployment host, include API key, update timestamps/fields, and log URL/status/results.
4) **LiveView & Routes** — Done
   - Deployment modal inside service dashboard for add/edit; health/version triggers per deployment; settings modal for services.
   - Deployment form includes automatic checks toggle and interval selector (1m, 2m, 5m, 10m, 30m, 1h, 2h, 6h, 12h, 24h).
5) **Service Detail Integration** — Done
   - Deployments listed with health badge (color-coded: success/warning/error), version display, and actions.
   - Service endpoints removed from main view (config templates not prominent).
   - Repository info condensed to horizontal layout; deployments are primary focus.
   - Automatic checks indicator shown with badge (clock icon + interval) when enabled.
   - Manual check buttons run asynchronously with loading states (spinning icon + disabled).
   - Last checked timestamps displayed with relative time formatting.
6) **Dashboard Metrics**
   - Still pending (deployment counts/health summary on dashboards).
7) **Automatic Checks Implementation**
   - Schema and UI complete; actual scheduler implementation NOT YET DONE.
   - No GenServer or background job runner implemented.
   - Fields are ready for future GenServer that will query `automatic_checks_enabled = true` deployments and schedule based on `check_interval_minutes`.
8) **Cleanup & Compatibility**
   - Legacy Clients/ServiceClients remain documented as deprecated; follow-up cleanup later.

## Risks & Decisions to Lock
- HTTP client behavior (timeouts, SSL errors) should return meaningful UI messages; default timeouts to avoid hanging LiveViews.
- Template interpolation: assume simple `{{host}}` replacement; explicitly strip protocol from host if users include it?
- Backfill strategy: only run when legacy tables exist; otherwise skip without failing.

### Newly agreed behaviors
- Health checks are mandatory for every deployment but expectation rules are configurable (e.g., require 200-only or a specific JSON shape).
- Version checks are optional per deployment; when enabled they can carry per-deployment expectations for parsing/validation.
- Health expectation shape: allowed statuses list plus optional expected JSON fragment; status outside expectations downgrades health from ok.
- Version expectation shape: optional allowed statuses list and a field name to read from JSON (plain text still works); failures record the check but don't block other actions.
- Service UX: clicking a service opens its dashboard; settings live under a separate button (no direct edit from the list).
- Service dashboards show deployments with manual health/version triggers; add/create flows will come after the dashboard wiring.
- Creating a deployment only records metadata/expectations; it does not install or deploy code.
- Endpoints remain defined at the service level (version/health templates with `{{host}}` placeholder); deployments carry the host (and optional API key) only.
- Logging: health/version checks log requested URL, status, parsing field expectations, and parsed values (or missing/empty cases) for visibility.
- Automatic checks are optional per deployment; when enabled, user selects interval from predefined options (1-1440 minutes).
- Service detail page emphasizes deployments as primary content with color-coded health badges (green/yellow/red) and relative timestamps.
- Manual check buttons show async loading states (spinning icon + "Checking..." + disabled) to provide immediate visual feedback.
- Deployment cards display automatic check status with info badge when enabled, showing interval in compact format (e.g., "Auto 5m", "Auto 2h").

## Testing Plan
- ExUnit coverage for context changesets/queries and check modules (ok/warning/down/error cases; JSON vs plain text versions).
- LiveView tests for deployment CRUD and manual triggers (button events update assigns and flash messages).
- Smoke test dashboard metrics to ensure queries respect user scoping.
