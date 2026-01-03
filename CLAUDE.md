# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Service Hub is a modular deployment orchestrator built with Elixir/Phoenix that manages:
- **Providers** - External code hosting instances (Gitea, GitHub) with OAuth/PAT authentication
- **Services** - Repositories hosted on providers
- **Clients** - Customer installations
- **ServiceClients** - Specific service deployments on client VMs

All configuration is database-driven with no hardcoded provider logic.

## Common Commands

```bash
# Development
mix setup              # Install deps, create DB, run migrations, setup assets
mix phx.server         # Start Phoenix server

# Database
mix ecto.migrate       # Run migrations
mix ecto.reset         # Drop, create, migrate, seed

# Testing
mix test               # Run all tests
mix test path/to/test.exs           # Run single test file
mix test path/to/test.exs:42        # Run specific test at line

# Quality
mix format             # Format code
mix precommit          # Full check: compile (warnings-as-errors), unlock unused deps, format, test

# Assets
mix assets.build       # Compile Tailwind + esbuild
```

## Architecture

### Provider Abstraction Layer

All external provider interactions go through a behaviour-based adapter system:

- `ServiceHub.ProviderAdapters.Behaviour` - Defines the contract (validate_connection, list_repositories, etc.)
- `ServiceHub.ProviderAdapters` - Dispatcher that routes to the correct adapter based on `provider_type.key`
- `ServiceHub.ProviderAdapters.Gitea` / `.GitHub` - Concrete implementations

**No direct HTTP calls outside adapters.** Use `Req` for HTTP within adapters.

### Context Modules

Context modules follow Phoenix conventions and always take `%Scope{}` as first argument:
- `ServiceHub.Providers` - Manages providers, provider_types, auth_types
- `ServiceHub.Services` - Manages services
- `ServiceHub.Clients` - Manages clients
- `ServiceHub.ServiceClients` - Manages service deployments

Access current user via `scope.user` in queries. In templates, use `@current_scope.user`.

### LiveView Patterns

**Async data loading pattern:**
1. Initialize assigns with `AsyncResult.loading()`
2. Trigger work with `start_async/3`
3. Handle results in `handle_async/3` using `AsyncResult.ok/1` or `AsyncResult.failed/2`
4. Render with `<.async_result>` component slots (`:loading`, `:failed`, `:let={result}`)
5. **Always include an error clause** in `handle_async/3` for `{:exit, reason}`

### Routing & Authentication

Routes requiring auth go in the existing `live_session :require_authenticated_user` block. Public routes use `live_session :current_user`. Never duplicate live_session names.

## Frontend Guidelines

- Use daisyUI theme colors (primary, secondary, error, success, etc.) - never hardcoded Tailwind colors like `bg-blue-500`
- Create components in dedicated files, not in `core_components.ex` unless truly app-wide
- Use LiveComponents for stateful/interactive pieces

## Elixir Constraints

- **Guards cannot call remote functions** - `String.trim/1`, `String.contains?/2` etc. are NOT allowed in guards
- Use `System.get_env/2` or `Envar.get/2` with second argument for defaults, not `|| default`
