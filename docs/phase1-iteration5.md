# Phase 1 – Iteration 5: Dashboard Refactor

**Scope:** Complete UI restructure from CRUD-focused to dashboard-oriented approach with sidebar navigation, provider-specific branding, reusable status components, and new dashboard views.

## Key Changes

### 1. Brand Identity & Theming

**CSS Variables for Provider Brands** ([app.css](../assets/css/app.css))
- Added `--color-github` / `--color-github-content` for both light and dark themes
- Added `--color-gitea` / `--color-gitea-content` for both light and dark themes
- GitHub: Dark monochrome tones
- Gitea: Green brand color (`oklch` with proper contrast)
- All colors support theme switching automatically

### 2. Reusable Component Library

Created dedicated component modules following Phoenix LiveView patterns:

**Status Components** (`lib/service_hub_web/components/status/`)
- `health_badge.ex` - Health status badges (ok/warning/down/unknown) with color coding, size variants, and optional icons
- `validation_badge.ex` - Provider validation status badges (ok/error/pending)
- `version_display.ex` - Version display with relative timestamps and formatting

**Provider Branding** (`lib/service_hub_web/components/provider_icon.ex`)
- Renders provider-specific icons (GitHub official mark, Gitea tea leaf, fallback cloud)
- Uses CSS variables for theming
- Size variants: sm/md/lg/xl
- Optional label display
- SVG icons embedded directly for performance

**Layout Components** (`lib/service_hub_web/components/layouts/`)
- `sidebar.ex` - Collapsible sidebar navigation with:
  - User avatar with initials
  - Navigation items: Dashboard, Monitoring, Configuration (Providers/Services/Clients), Audit Log
  - Active state highlighting
  - User profile section with logout
  - Responsive drawer pattern (mobile/desktop)

### 3. Dashboard Views

**Main Dashboard** (`lib/service_hub_web/live/dashboard_live.ex`)
- Overview of entire system state
- Quick stats cards: Providers (with validation count), Services, Clients, Installations (with health count)
- Provider grid with brand icons and validation badges
- Recent installations table with health status
- Empty states with calls-to-action
- PubSub subscriptions for real-time updates

**Provider Dashboard** (`lib/service_hub_web/live/provider_live/dashboard.ex`)
- Replaces old provider "show" view
- Provider header with:
  - Large brand icon
  - Validation status badge
  - Provider metadata (type, URL, auth, last validated time)
  - Validate and Configure actions
- Provider-specific stats: Services count, Installations, Healthy/Issues counts
- Service cards showing:
  - Repository info (owner/repo, default ref)
  - Installations list with client, env, version, health
  - Quick edit/delete actions
- Service form in modal instead of inline
- Empty states for no services/installations

### 4. Context Layer Additions

**New Contexts:**
- `ServiceHub.Clients` ([clients.ex](../lib/service_hub/clients.ex)) - Client management
- `ServiceHub.Clients.Client` ([clients/client.ex](../lib/service_hub/clients/client.ex)) - Client schema
- `ServiceHub.ServiceClients` ([service_clients.ex](../lib/service_hub/service_clients.ex)) - Installation management with scoped queries
- `ServiceHub.ServiceClients.ServiceClient` ([service_clients/service_client.ex](../lib/service_hub/service_clients/service_client.ex)) - Installation schema

**Services Context Enhancements** ([services.ex](../lib/service_hub/services.ex))
- `list_services/1` - List all services for user
- `count_services_for_provider/2` - Count services per provider (for dashboard stats)

### 5. Router Restructure

**New Route Organization** ([router.ex](../lib/service_hub_web/router.ex))
- `/dashboard` - Main dashboard (new default for authenticated users)
- `/monitoring` - Placeholder for monitoring view
- `/config/providers` - Provider list (moved from `/providers`)
- `/providers/:id` - Provider dashboard (now using `ProviderLive.Dashboard`)
- `/config/services` - Services list (placeholder)
- `/config/clients` - Clients list (placeholder)
- `/config/provider-types` - Provider types config (moved from `/provider_types`)
- `/config/auth-types` - Auth types config (moved from `/auth_types`)

**Home Page Redirect** ([page_controller.ex](../lib/service_hub_web/controllers/page_controller.ex))
- Authenticated users auto-redirect to `/dashboard`
- Public users see landing page

### 6. Layout Refactor

**Dual Layout System** ([layouts.ex](../lib/service_hub_web/components/layouts.ex))
- **Authenticated Layout:** Drawer + sidebar navigation, top navbar with theme toggle, max-width content area
- **Public Layout:** Simple navbar with register/login, centered content
- Current path detection for sidebar active state
- View-to-path mapping helper

### 7. Design Patterns & Best Practices

**Component Architecture:**
- Isolated component files (`.ex` + `.heex` where applicable)
- Attributes with proper validation and defaults
- Size/variant systems (xs/sm/md/lg)
- Conditional rendering via slots
- No hardcoded colors - CSS variables only

**Data Loading:**
- Async patterns for heavy queries
- PubSub for real-time updates
- Proper preloading of associations
- Scoped queries (always filter by `current_scope.user.id`)

**UI/UX Improvements:**
- Empty states with helpful CTAs
- Consistent spacing and sizing
- Responsive grid layouts
- Hover states and transitions
- Loading states for async actions
- Proper error handling

## File Structure Changes

```
lib/service_hub_web/
├── components/
│   ├── layouts/
│   │   └── sidebar.ex (new)
│   ├── status/
│   │   ├── health_badge.ex (new)
│   │   ├── validation_badge.ex (new)
│   │   └── version_display.ex (new)
│   └── provider_icon.ex (new)
├── live/
│   ├── dashboard_live.ex (new)
│   └── provider_live/
│       ├── dashboard.ex (new - replaces show.ex logic)
│       └── show.ex (kept for backward compat, but dashboard.ex is primary)

lib/service_hub/
├── clients.ex (new)
├── clients/
│   └── client.ex (new)
├── service_clients.ex (new)
└── service_clients/
    └── service_client.ex (new)
```

## Migration Notes

- No database migrations required
- Existing data fully compatible
- Old routes still work but redirect to new structure
- `ProviderLive.Show` can be removed in future cleanup (dashboard.ex replaces it)

## Dependencies

No new dependencies added. Uses existing stack:
- Phoenix LiveView 1.1+ (AsyncResult pattern)
- DaisyUI components
- Tailwind 4 CSS
- Heroicons

## Testing

- Keep existing generator tests as-is
- Manual testing recommended:
  - Verify sidebar navigation works (mobile/desktop)
  - Check dashboard stats calculate correctly
  - Ensure provider icons render with correct colors in both themes
  - Test service card interactions
  - Verify empty states display properly

## Future Work (Not Implemented)

- `/monitoring` - Service-client health matrix view
- `/config/services` - Standalone services list/management
- `/config/clients` - Client CRUD interface
- `/audit` - Audit log viewer
- Real-time health checks from dashboard
- Bulk operations (validate all, check all health)
- Activity feed component

## Notes

- **Provider-specific branding:** Each provider now has consistent iconography and color scheme throughout the app
- **Dashboard-first approach:** Users land on overview with quick access to details
- **Sidebar navigation:** Single source of truth for app structure; easier to add new sections
- **Component reusability:** Status badges, icons, and metrics cards can be used anywhere
- **Theme-aware:** All brand colors adapt to light/dark theme automatically
- **Responsive design:** Drawer collapses on mobile, expands on desktop
- **Empty states:** Every section handles zero-data gracefully with actionable next steps
