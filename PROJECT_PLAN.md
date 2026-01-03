# Service Hub - Project Plan

## Overview

Service Hub is a deployment orchestrator for managing self-hosted services backed by Git repositories. It provides centralized management of code providers (Gitea, GitHub), services (repositories), and their deployments across different environments.

## Core Concepts

### Provider
External code hosting instance (Gitea, GitHub, GitLab).
- Stores connection credentials and API configuration
- Supports multiple authentication methods (PAT, OAuth, GitHub App)
- Validated via API connection test

### Service
A repository hosted on a provider.
- Linked to a specific provider
- Contains version and health endpoint templates
- Defines the default branch/ref for deployments

### Deployment
A specific installation of a service on a host. **Replaces the previous Client/ServiceClient model.**
- Each deployment represents one running instance of a service
- Has its own host URL, environment label, and optional API key
- Tracks current version and health status independently

### Simplified Model

```
Provider (Gitea/GitHub)
  └── Service (repository)
        └── Deployment (host instance)
             - host: "app.customer.com"
             - env: "production"
             - current_version: "v1.2.3"
             - health_status: "ok"
```

This removes the need for a separate "Client" entity. If you need to group deployments by customer, you can use naming conventions or add a simple `client_name` field to deployments.

---

## Current Status

### Completed (Phase 1)

1. **Provider Management** ✅
   - CRUD for providers
   - Provider type & auth type configuration
   - Gitea adapter with PAT authentication
   - GitHub adapter with OAuth, PAT, and GitHub App support
   - Connection validation
   - Repository listing via provider API
   - Branch listing via provider API

2. **Service Management** ✅
   - CRUD for services
   - Repository selector from provider API
   - Branch selector from provider API
   - Version/health endpoint templates

3. **System Configuration** ✅
   - Provider Types management UI
   - Auth Types management UI with compatible providers
   - Danger zone for destructive operations
   - Gitea token generation from username/password

4. **UI Foundation** ✅
   - DaisyUI theming with dark/light modes
   - Card-based layouts
   - Async loading patterns with skeletons
   - Provider dashboard with service list

### In Progress

5. **Deployments** 🔄
   - Migrate from Client/ServiceClient to unified Deployment model
   - Deployment CRUD
   - Version check engine
   - Health check engine

---

## Phase 1 Remaining Work

### 1. Deployment Management

Replace the Client + ServiceClient entities with a single Deployment entity.

**Schema: `deployments`**
```
- id
- service_id (FK)
- name (display name, e.g., "Acme Corp Production")
- host (e.g., "app.acme.com")
- env (e.g., "production", "staging")
- api_key (optional, for authenticated endpoints)
- current_version
- last_version_checked_at
- last_health_status ("unknown", "ok", "warning", "down")
- last_health_checked_at
- timestamps
```

**UI Routes:**
- `/providers/:provider_id/services/:service_id/deployments` - List deployments
- `/providers/:provider_id/services/:service_id/deployments/new` - New deployment
- `/providers/:provider_id/services/:service_id/deployments/:id` - Deployment detail/edit

**Features:**
- Add deployment from service detail page
- View all deployments with version/health indicators
- Manual version check trigger
- Manual health check trigger

### 2. Version Check Engine

**Flow:**
1. Build URL from service template: `https://{{host}}/api/version`
2. Interpolate deployment's `host` value
3. Add `api_key` header if present
4. Make HTTP request
5. Parse response (JSON with `version` field or plain text)
6. Update deployment: `current_version`, `last_version_checked_at`
7. Create audit log entry

**Implementation:**
- `ServiceHub.Checks.Version` module
- Called manually from UI initially
- Later: scheduled via Quantum or Oban

### 3. Health Check Engine

**Flow:**
1. Build URL from service template: `https://{{host}}/api/health`
2. Interpolate deployment's `host` value
3. Add `api_key` header if present
4. Make HTTP request
5. Determine status:
   - 2xx → "ok"
   - 5xx → "down"
   - Timeout/connection error → "down"
   - 4xx → "warning"
6. Update deployment: `last_health_status`, `last_health_checked_at`
7. Create audit log entry

### 4. Service Detail View

Enhanced service page showing:
- Service info (repo, default branch, endpoints)
- Deployments list with version/health badges
- Quick actions (check all versions, check all health)
- Add deployment button

### 5. Dashboard Improvements

Global overview:
- Services count per provider
- Deployments count
- Health status summary (X ok, Y warning, Z down)
- Recent activity feed

---

## Phase 2 - Workflow Orchestration (Future)

### Workflow Definitions
- `service_workflows` table linking services to provider workflows
- Workflow metadata (name, trigger type, parameters)

### Workflow Dispatch
- Trigger workflows via provider API
- Track run status
- Poll or webhook for completion

### Workflow Runs
- `workflow_runs` table
- States: pending, running, success, failed, cancelled
- Link to deployment for deploy workflows

---

## Phase 3 - Monitoring & Live Updates (Future)

### Dashboards
- Service × Deployment matrix view
- Version diff highlighting
- Health trend graphs

### Live Updates
- Phoenix PubSub for real-time UI updates
- Push version/health changes to connected clients
- Activity stream

### Logs
- Fetch workflow logs from provider
- Store log snapshots
- Log viewer UI

---

## Phase 4 - Pipelines & Rules (Future)

### Deployment Pipelines
- Multi-step workflows: migrate → deploy → verify
- Rollback on failure
- Pipeline templates

### Deployment Rules
- Maintenance windows
- Manual approval gates
- Environment promotion rules

---

## Phase 5 - Multi-Provider & Access Control (Future)

### Additional Providers
- GitLab adapter
- Normalize capabilities across providers

### RBAC
- User roles (admin, operator, viewer)
- Resource-level permissions
- Audit trail per user

---

## Database Migration Plan

### Step 1: Create deployments table
New table with all deployment fields.

### Step 2: Migrate existing data (if any)
```sql
INSERT INTO deployments (service_id, name, host, env, ...)
SELECT sc.service_id, c.name, sc.host, sc.env, ...
FROM service_clients sc
JOIN clients c ON c.id = sc.client_id;
```

### Step 3: Remove old tables
Drop `service_clients` and `clients` tables after successful migration.

---

## Technical Guidelines

See [CLAUDE.md](./CLAUDE.md) for:
- Common commands
- Architecture patterns
- LiveView async patterns
- Frontend guidelines
- Elixir constraints

---

## File Structure

```
lib/service_hub/
  ├── accounts/          # User authentication
  ├── providers/         # Provider, ProviderType, AuthType
  ├── services/          # Service schema
  ├── deployments/       # Deployment schema (NEW)
  ├── checks/            # Version & Health check engines (NEW)
  └── provider_adapters/ # Gitea, GitHub adapters

lib/service_hub_web/
  ├── components/        # Reusable UI components
  └── live/
      ├── provider_live/ # Provider views
      ├── service_live/  # Service views
      ├── deployment_live/ # Deployment views (NEW)
      └── dashboard_live/  # Main dashboard
```
