
# Service Hub – Roadmap (Part 1)

## 1. Project Vision

Build a modular full-stack deployment orchestrator that centralizes the management of:

- Providers (starting with Gitea, later GitHub/GitLab)
- Services (repos per provider)
- Clients (installations of a service)
- ServiceClients (service deployed on a client VM)
- Future: Workflows, workflow runs, orchestration pipelines

The app should:

- Use providers’ APIs to trigger and manage workflows
- Track versions per client per service via HTTP endpoints
- Perform health checks and maintain historical status/versions
- Keep a complete audit trail
- Remain fully provider-agnostic using behavior-based adapters
- Store **all configuration in the database**, no hardcoded rules

---

## 2. High-Level Architecture

### 2.1 Core Domain Entities

- **Provider**  
  External code hosting instance (Gitea/GitHub/GitLab).  
  Includes base URL, provider_type, auth_type, auth_data.

- **ProviderType**  
  Defines a provider kind (e.g., gitea, github) and its required_fields map used to render provider-specific inputs.

- **AuthType**  
  Defines an auth method (e.g., pat, oauth) and its required_fields map used to render auth-specific inputs.

- **Service**  
  A repo hosted on a provider.  
  Includes owner, repo name, default ref, version/health URL templates.

- **Client**  
  A customer or institution.

- **ServiceClient**  
  Represents a specific installation of a Service on a client VM.

- **AuditLog**  
  Records every action taken through the app.

### 2.2 Provider Abstraction Layer

Define a provider behaviour that all provider adapters must implement:

Create the first adapter: `Provider.Gitea`.

**No direct HTTP calls outside the adapters.**

### 2.3 Database Strategy

- Single Postgres instance
- All data-driven configuration
- No hardcoded provider names, workflow definitions, service types, or repo structures

### 2.4 Technology Baseline & Frontend Guidelines

**Active constraint:** Do not write any project documentation yet unless specifically asked for or Phoenix generated; focus on implementation only.
**Testing note:** Keep generator-produced tests as-is; no additional tests needed right now.

- Backend stack: Elixir `~> 1.15`, Phoenix `~> 1.8.2` with LiveView `~> 1.1` (many new stuff in this versions), Ecto + Postgres, HTTP via `Req` inside provider adapters, Bandit for HTTP serving, `Jason` for JSON, and `Swoosh` for email.
- Frontend build: HEEx templates, Tailwind + CSS variables defined in `assets/css/app.css`, esbuild for assets, Heroicons for icons.
- Use **Phoenix LiveView** for all user-facing interfaces.
- Create components in dedicated files (e.g., `my_component.ex` and `my_component.html.heex`) to keep concerns isolated.
- Use LiveComponents for stateful or highly interactive pieces that need fine-grained control.
- Do not add new components to `core_components.ex` unless they are genuinely reusable, application-wide core elements. Prefer creating new component modules.
- Do not use hardcoded Tailwind CSS color classes like `bg-blue-500` or `text-red-700`. Instead, use CSS variables defined in `app.css` to align with the branding and theme (e.g., `bg-primary`, `text-danger`).

### 2.5 Elixir Guard Constraints

**Important:** Guards in Elixir can only use a limited set of functions and operators. Remote function calls like `String.trim/1`, `String.contains?/2`, or any module function cannot be invoked inside guards.

- **Error example:** `when is_binary(value) and String.trim(value) != ""` → **NOT ALLOWED**
- **Solution:** Move the logic outside the guard or use only allowed guard functions (type checks, comparison operators, arithmetic operators, and a small set of BIFs like `is_binary/1`, `is_nil/1`, `byte_size/1`, etc.)
- **Correct approach:** Validate the value in the function body after pattern matching, not in the guard clause.

See the [Elixir Guards documentation](https://hexdocs.pm/elixir/patterns-and-guards.html#guards) for the complete list of allowed functions in guards.

---

## 3. Roadmap Phases Overview

- **Phase 1** — Data management, provider validation, endpoint checks  
  (foundation, no hardcoded behaviour)

- **Phase 2** — Workflow definitions + workflow dispatch orchestration

- **Phase 3** — Monitoring dashboards, LiveView, PubSub, log fetching

- **Phase 4** — Sequencing: DB migration → deploy → health → rollback  
  + client-level rules (windows, approvals)

- **Phase 5** — Multi-provider support + RBAC

---

## 4. Phase 1 — Data Management, Provider Validation & Health Checks

This phase must not contain any hardcoded behaviour; everything must be configurable via DB + provider adapters.

### 4.1 Database Schema (Phase 1 version)

Create schemas and migrations for:

#### `providers`
- id  
- user_id  
- name  
- base_url  
- provider_type_id (FK)  
- auth_type_id (FK)  
- auth_data (jsonb, defaults to `{}`)  
- timestamps  

#### `provider_types`
- id  
- user_id  
- name  
- key (unique per user)  
- required_fields (jsonb, defaults to `{}`)  
- timestamps  

#### `auth_types`
- id  
- user_id  
- name  
- key (unique per user)  
- required_fields (jsonb, defaults to `{}`)  
- timestamps  

#### `services`
- id  
- provider_id  
- name  
- owner  
- repo  
- default_ref  
- version_endpoint_template  
- healthcheck_endpoint_template  
- timestamps

#### `clients`
- id  
- name  
- code  
- timestamps

#### `service_clients`
- id  
- service_id  
- client_id  
- host  
- env  
- api_key  
- current_version  
- last_version_checked_at  
- last_health_status (`"unknown"`, `"ok"`, `"warning"`, `"down"`)  
- last_health_checked_at  
- timestamps

#### `audit_logs`
- id  
- user_id (root for now)  
- action  
- entity_type  
- entity_id  
- metadata (jsonb)  
- inserted_at

---

### 4.2 Provider Abstraction Implementation

Implement `ProviderBehaviour` with:

- `validate_connection/1`  
  Check token validity through API request.

- `fetch_repo_metadata/2`  
  Verify repository existence via provider API.

- `dispatch_workflow/2`  
  Implement mapping to Gitea endpoint:  
  `/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`  
  (Not used in Phase 1, but fully defined.)

**All logic must use the adapter, never provider-specific conditionals.**

---

### 4.3 Provider & Service Management Flows

Implement CRUD operations:

#### Providers
- create/update/delete
- validation via `validate_provider_connection/1`
- provider_type and auth_type chosen from DB (no free-text)
- store results in audit logs

#### Services
- create/update
- validate that:
  - provider exists & connection works
  - repo exists via `fetch_repo_metadata/2`
  - endpoint templates are valid URL templates
- audit all changes

All data must be defined by the user; nothing is hardcoded.

---

### 4.4 Client & ServiceClient Management

Implement CRUD and validation:

- Clients: name + code
- ServiceClients:
  - host + env mandatory
  - api_key optional
  - service_id + client_id must exist
  - audit changes

No special-case rules per service/client; everything is data-driven.

---

### 4.5 Version & Health Check Engine

Implement Phase 1 pipelines:

#### Version Check
- Build URL from template:
  `https://{{host}}/api/version` → interpolate `host`
- Add api_key if needed
- Parse JSON or raw string version
- Update DB:
  - `current_version`
  - `last_version_checked_at`
- Add audit log with old/new version

#### Health Check
- Same process but for the health endpoint
- Map result to enum: `"ok"`, `"warning"`, `"down"`
- Update DB + audit

**Automated DB sync:**  
When remote version differs from stored version → update DB immediately.

---

### 4.6 Minimal UI/API for Phase 1

Create simple interfaces (UI or REST):

- Providers:
  - CRUD
  - Validate connection

- Services:
  - CRUD
  - Validate repo mapping

- Clients:
  - CRUD

- ServiceClients:
  - CRUD
  - Trigger version check
  - Trigger health check

View structure:

- Provider → details + validation status
- Service → clients with quick version/health indicators
- ServiceClient → fields + last version/health info
- Provider form uses selects for provider/auth types and renders structured inputs from their `required_fields` maps instead of raw JSON fields.

**No workflow UI yet.**

# Deployment Orchestrator – Roadmap (Part 2)

## 5. Phase 2 — Workflow Definitions & Dispatch Orchestration (Outline)

(Not implemented in Phase 1; included to guide future agents.)

### 5.1 Database Additions
- `service_workflows`
- `workflow_runs`

### 5.2 Workflow Engine
- Trigger workflow dispatch through provider adapter
- Store run metadata
- Manage run states: pending, running, success, failed, cancelled

### 5.3 Tracking Workflow Runs
- Poll provider for status or
- Accept callback from workflow to internal API endpoint
- Update workflow_runs accordingly
- Record audit logs

---

## 6. Phase 3 — Monitoring, PubSub & Logs (Outline)

### 6.1 Dashboards
- Global grid: service × client × version × health
- Detail pages: workflow runs per service/client

### 6.2 Live Updates
- LiveView + Phoenix.PubSub
- Push updates when:
  - version changes
  - health changes
  - workflow_run changes

### 6.3 Logs
- Fetch logs on demand from provider API
- Store minimal log snapshots with TTL
- Display logs in UI

---

## 7. Phase 4 — Workflow Pipelines & Client-Level Rules (Outline)

### 7.1 Workflow Sequencing
- DB migration → deploy → health check
- Rollback on failure

### 7.2 Client Rules
- Deploy windows (start/end)
- `requires_manual_approval`
- Enforce rules in dispatch engine

---

## 8. Phase 5 — Multi-Provider & RBAC (Outline)

### 8.1 Multi-Provider Extensions
- Add GitHub adapter
- Normalize capabilities across providers

### 8.2 RBAC
- Users, roles, permissions
- Access control per provider/service/client

---

_End of Part 2_


<!-- phoenix-gen-auth-start -->
## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A `live_session :current_user` scope - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope - for routes that require authentication, similar to the plug with the same name
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session` as described below**

### Routes that require authentication

LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{ServiceHubWeb.UserAuth, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the __existing__ `:current_user` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{ServiceHubWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->
