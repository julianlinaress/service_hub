# Repository Guidelines

## Project Structure & Module Organization
- `lib/service_hub` holds core contexts and domain logic; `lib/service_hub_web` contains routers, LiveViews, controllers, and components.
- Front-end assets live in `assets/js` and `assets/css`; compiled artifacts are generated via esbuild/tailwind.
- Database migrations and seeds sit in `priv/repo`; runtime and env-specific settings are under `config`.
- Tests mirror the app layout in `test/service_hub` and `test/service_hub_web`, with helpers in `test/support`.
- Use `docs/` for longer-form notes and ADR-style references when needed.

## Build, Test, and Development Commands
- `mix setup` installs deps, prepares the database, and fetches/builds assets.
- `mix phx.server` starts the dev server (ensure DB is running); `PHX_SERVER=true mix release.start` for releases.
- `mix assets.build` rebuilds JS/CSS; `mix assets.deploy` minifies and digests for production.
- `mix test` uses the alias to create/migrate the test DB automatically; add paths to scope (e.g., `mix test test/service_hub_web`).
- `mix precommit` enforces compile warnings-as-errors, cleans unused deps, formats, and runs the suite—use before opening a PR.

## Coding Style & Naming Conventions
- Run `mix format` before committing; prefer 2-space indentation and pipeline-friendly clauses.
- Module names follow `ServiceHub.*` for core logic and `ServiceHubWeb.*` (e.g., `FooLive`, `FooController`) for web layers; file names stay snake_case.
- HEEx templates stay colocated with their components; JS/TS hooks use `camelCase` and live in `assets/js`.
- Favor clear pattern matching, guard clauses, and explicit changesets over ad-hoc validation.

## Testing Guidelines
- ExUnit is the primary framework; tests end with `_test.exs` and mirror module names.
- Use `describe` blocks for readability and shared setup; isolate DB state with the sandbox helpers in `test/support`.
- For coverage or debugging, run `MIX_ENV=test mix test --cover` or `mix test --trace`.
- Stub external calls where possible; prefer seeded fixtures over hitting live services.

## Commit & Pull Request Guidelines
- Follow the observed Conventional Commit style: `feat:`, `fix:`, `chore:`, `docs:` with imperative phrasing.
- Keep commits focused and small; update docs/tests alongside code.
- PRs should summarize the change, link relevant issues, and include screenshots for UI-facing updates.
- Run `mix precommit` locally and note any manual steps (migrations, seeds) in the PR description.

## Security & Configuration Tips
- Secrets load from `.env` via Envar; override with `ENV_FILE` when needed. Do not commit env files or secrets.
- Required env keys include `DATABASE_URL`, `SECRET_KEY_BASE`, `GITHUB_OAUTH_CLIENT_ID/SECRET`, and `PHX_HOST`; set `PORT` to change the HTTP port.
- For prod/startup, set `PHX_SERVER=true` and configure `POOL_SIZE`/`ECTO_IPV6` as needed; consider enabling `force_ssl` in `config/prod.exs`.
