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
- No background scheduling (Quantum/Oban) or recurring checks.
- No realtime PubSub updates; UI refresh relies on redirects/patches.
- No RBAC or per-user filtering changes beyond existing scope helpers.
- No pipeline/workflow orchestration; deployment is host metadata + checks only.

## Work Breakdown
1) **Schema & Migration** — Done
   - Deployments table added; backfill path from clients/service_clients included.
   - Service endpoint templates restored (version/health with `{{host}}`); deployment endpoints removed.
2) **Context Layer** — Done
   - `ServiceHub.Deployments` with scoped CRUD, validations (host/env/name uniques per service).
3) **Check Engines** — Done
   - `ServiceHub.Checks.Version/Health` use service templates + deployment host, include API key, update timestamps/fields, and log URL/status/results.
4) **LiveView & Routes** — Done
   - Deployment modal inside service dashboard for add/edit; health/version triggers per deployment; settings modal for services.
5) **Service Detail Integration** — Done
   - Deployments listed with health badge, version display, and actions; service endpoints shown from templates.
6) **Dashboard Metrics**
   - Still pending (deployment counts/health summary on dashboards).
7) **Cleanup & Compatibility**
   - Legacy Clients/ServiceClients remain documented as deprecated; follow-up cleanup later.

## Risks & Decisions to Lock
- HTTP client behavior (timeouts, SSL errors) should return meaningful UI messages; default timeouts to avoid hanging LiveViews.
- Template interpolation: assume simple `{{host}}` replacement; explicitly strip protocol from host if users include it?
- Backfill strategy: only run when legacy tables exist; otherwise skip without failing.

### Newly agreed behaviors
- Health checks are mandatory for every deployment but expectation rules are configurable (e.g., require 200-only or a specific JSON shape).
- Version checks are optional per deployment; when enabled they can carry per-deployment expectations for parsing/validation.
- Health expectation shape: allowed statuses list plus optional expected JSON fragment; status outside expectations downgrades health from ok.
- Version expectation shape: optional allowed statuses list and a field name to read from JSON (plain text still works); failures record the check but don’t block other actions.
- Service UX: clicking a service opens its dashboard; settings live under a separate button (no direct edit from the list).
- Service dashboards show deployments with manual health/version triggers; add/create flows will come after the dashboard wiring.
- Creating a deployment only records metadata/expectations; it does not install or deploy code.
- Endpoints remain defined at the service level (version/health templates with `{{host}}` placeholder); deployments carry the host (and optional API key) only.
- Logging: health/version checks log requested URL, status, parsing field expectations, and parsed values (or missing/empty cases) for visibility.

## Testing Plan
- ExUnit coverage for context changesets/queries and check modules (ok/warning/down/error cases; JSON vs plain text versions).
- LiveView tests for deployment CRUD and manual triggers (button events update assigns and flash messages).
- Smoke test dashboard metrics to ensure queries respect user scoping.
