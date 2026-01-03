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
1) **Schema & Migration**
   - Create `deployments` table with fields from PROJECT_PLAN.md (service_id FK, name, host, env, api_key, current_version, last_version_checked_at, last_health_status, last_health_checked_at, timestamps).
   - Optional migration step to backfill from `clients` + `service_clients` if data exists (guarded to avoid failures on empty tables).
2) **Context Layer**
   - New schema module `ServiceHub.Deployments.Deployment` with validations (required fields, host format, env presence, unique constraint on service_id+name and service_id+host).
   - `ServiceHub.Deployments` context: list/get/create/update/delete with user scoping via service/provider ownership; helper queries for counts and preload of service/provider.
3) **Check Engines**
   - `ServiceHub.Checks.Version` and `ServiceHub.Checks.Health`: build URL from service templates, interpolate host, include `api_key` header, handle JSON/plain text version responses, classify health statuses per spec, and update deployment fields + timestamps.
   - Return tagged tuples for UI feedback; log/audit stub via existing instrumentation pattern.
4) **LiveView & Routes**
   - Router scope: nested deployment routes under provider/service; index/list, new, edit, detail.
   - LiveViews/forms for deployment CRUD; reuse status components for badges; inputs for host/env/api_key; show last check times and current version.
5) **Service Detail Integration**
   - Update service detail page to list deployments inline with quick actions (check version/health per deployment and bulk for all in the service).
   - Provide empty state CTA to add first deployment.
6) **Dashboard Metrics**
   - Add deployment count + health summary to main/provider dashboards using context helpers; keep UI minimal to avoid layout churn.
7) **Cleanup & Compatibility**
   - Mark `ServiceHub.Clients` and `ServiceHub.ServiceClients` as deprecated in docs/comments; leave code intact for migration window.
   - Update docs with new flows and API expectations.

## Risks & Decisions to Lock
- HTTP client behavior (timeouts, SSL errors) should return meaningful UI messages; default timeouts to avoid hanging LiveViews.
- Template interpolation: assume simple `{{host}}` replacement; explicitly strip protocol from host if users include it?
- Backfill strategy: only run when legacy tables exist; otherwise skip without failing.

## Testing Plan
- ExUnit coverage for context changesets/queries and check modules (ok/warning/down/error cases; JSON vs plain text versions).
- LiveView tests for deployment CRUD and manual triggers (button events update assigns and flash messages).
- Smoke test dashboard metrics to ensure queries respect user scoping.
