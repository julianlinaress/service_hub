# Improvements Plan

This document lists concrete, self-contained improvements for Claude Code to implement.
Each task is scoped to a single commit. Run `mix precommit` before each commit.

---

## Task 1 — Fix dead dashboard query

Commit message: fix: replace dead ServiceClients query in dashboard with Deployments

In lib/service_hub_web/live/dashboard_live.ex, replace the load_installations/1 function.
It currently queries ServiceClients which is always empty for new users.

Replace it with a query using ServiceHub.Deployments that loads recent deployments
with last_health_checked_at not nil, ordered by last_health_checked_at desc, limit 10.
Preload service and service.provider on each deployment.

Update the template section "Recent Health Checks" to render deployment fields:
- Name: deployment.name (was sc.service.name)
- Sub-label: deployment.env (was sc.client.name · sc.env)
- Version: deployment.current_version
- Health badge: deployment.last_health_status

Remove the ServiceClients alias from the LiveView.

---

## Task 2 — Add /healthz endpoint

Commit message: feat: add /healthz endpoint for container health checks

Create lib/service_hub_web/controllers/health_controller.ex with a single check/2
action that calls send_resp(conn, 200, "ok").

Add a route in lib/service_hub_web/router.ex in the public scope "/" block with no
auth pipeline: GET /healthz -> HealthController :check

Update docker-compose.prod.yml phoenix healthcheck to use /healthz instead of /.

Add a test in test/service_hub_web/controllers/health_controller_test.exs that GETs
/healthz and asserts a 200 response with body "ok".

---

## Task 3 — Debounce manual check buttons

Commit message: fix: debounce manual health and version check buttons

In lib/service_hub_web/live/service_live/detail.ex:

Add :last_manual_check_at to mount assigns, set to nil.

In handle_event for check-health and check-version, before starting the async task,
check if last_manual_check_at is within the last 10 seconds using DateTime.diff.
If so, put a flash info "Please wait before running another check" and return noreply
without starting the task.

Set :last_manual_check_at to DateTime.utc_now() when a check starts.
Reset it to nil in both the ok and exit clauses of handle_async for both check types.

---

## Task 4 — Wrap automation target sync in transaction

Commit message: fix: wrap deployment mutations and automation target sync in transaction

In lib/service_hub/deployments.ex:

In create_deployment/2, wrap the Repo.insert call and the sync_automation_targets/1
call together in a Repo.transaction. The function should return {:ok, deployment} on
success and propagate {:error, reason} on failure.

In update_deployment/2, same pattern — wrap Repo.update and sync_automation_targets
in a single transaction.

The delete_deployment/2 function already uses a transaction; verify it is correct.

All Repo calls inside sync_automation_targets participate in the ambient transaction
automatically so no changes are needed inside that function.

---

## Task 5 — Emit telemetry for check results

Commit message: feat: emit telemetry events for health and version check results

In lib/service_hub/workers/check_helpers.ex, add a private function emit_check_telemetry
that takes automation_id, target_id, status, and duration_ms and calls:

  :telemetry.execute(
    [:service_hub, :checks, :completed],
    %{duration_ms: duration_ms},
    %{automation_id: automation_id, target_id: target_id, status: status}
  )

Call this from the end of execute_check/2 in both HealthCheckWorker and VersionCheckWorker,
after insert_run_record is called, passing the values already in scope.

In lib/service_hub_web/telemetry.ex, add to the metrics/0 list:

  summary("service_hub.checks.completed.duration_ms",
    tags: [:automation_id, :status]
  )

---

## Task 6 — Split Notifications context

Commit message: refactor: split Notifications context into focused submodules

Extract from lib/service_hub/notifications.ex into three new files:

lib/service_hub/notifications/channels.ex
  Move: list_channels, get_channel!, create_channel, update_channel, delete_channel,
  change_channel, enqueue_channel_test_notification, and all private helpers that serve
  only channel operations (normalize_channel_attrs, maybe_attach_telegram_refs,
  maybe_attach_telegram_refs_from_config, build_telegram_channel_config).

lib/service_hub/notifications/rules.ex
  Move: list_service_rules, get_service_rule!, create_service_rule, update_service_rule,
  delete_service_rule, change_service_rule, and the private verify_service_access and
  verify_channel_access helpers.

lib/service_hub/notifications/telegram_accounts.ex
  Move: list_telegram_accounts, list_telegram_destinations, discover_telegram_destinations,
  and the private helpers resolve_discovery_account, find_or_create_telegram_account,
  find_or_create_telegram_destination, get_telegram_account.

Keep lib/service_hub/notifications.ex as a facade that delegates every public function
to the appropriate submodule using defdelegate. This preserves all existing call sites
in LiveViews without any changes.

The shared private helpers normalize_id, get_value, put_value, to_existing_atom, and
present? should be extracted into a private lib/service_hub/notifications/helpers.ex
module and imported by the submodules that need them.

---

## Task 7 — Add EventHandler tests

Commit message: test: add tests for Notifications.EventHandler

Create test/service_hub/notifications/event_handler_test.exs.

Setup: create a user scope, provider, service, and a telegram notification channel.
Create a service_notification_rule linking the service to the channel with health alert
and warning enabled and notify_on_manual true.

Test 1: enqueue_deliveries/1 creates a delivery attempt and enqueues a delivery job
  - Call Events.emit to persist an event with name "health.alert" and a valid service_id
  - Call EventHandler.enqueue_deliveries with that event map
  - Assert one DeliveryAttempt record exists in the database with status "pending"
  - Assert a NotificationDeliveryWorker job is enqueued (use assert_enqueued)

Test 2: enqueue_deliveries/1 respects the only_channel_id option
  - Create a second channel not linked to any rule
  - Call enqueue_deliveries with only_channel_id set to the second channel id
  - Assert one DeliveryAttempt is created for that specific channel

Test 3: enqueue_deliveries/1 skips channels when no matching rule
  - Emit a "version.alert" event for a service with no version alert rule enabled
  - Call enqueue_deliveries
  - Assert no DeliveryAttempt records are created

Test 4: enqueue_deliveries/1 skips manual source when notify_on_manual is false
  - Update the rule to have notify_on_manual false
  - Emit a "health.alert" event with tags source "manual"
  - Assert no DeliveryAttempt records are created

Test 5: enqueue_deliveries/1 returns ok when event_id is nil
  - Call enqueue_deliveries with a map that has no id key
  - Assert it returns :ok without raising

---

## Task 8 — Add proper health and version check unit tests

Commit message: test: replace HTTP integration tests with stubbed unit tests for check engines

The existing tests in test/service_hub/checks/health_test.exs make real HTTP requests
and only assert the function does not crash. Replace them with stub-based tests.

Add to config/test.exs:
  config :service_hub, :http_client, ServiceHub.HTTPClientStub

Create test/support/stubs/http_client_stub.ex that implements a simple stub which reads
responses from the process dictionary key :http_responses keyed by URL pattern.

In lib/service_hub/checks/health.ex and lib/service_hub/checks/version.ex, replace the
direct Req.request call with a call through a configured client:

  defp http_client do
    Application.get_env(:service_hub, :http_client, Req)
  end

  # then call: http_client().request(req_opts)

Write the following test cases for Health.run/2 using the stub:

  - 200 response with matching expected_json returns {:ok, deployment}
  - 200 response with non-matching expected_json returns {:warning, ...}
  - 500 response returns {:error, ...} and sets last_health_status to "down"
  - 404 response returns {:warning, ...} and sets last_health_status to "warning"
  - Network error (stub returns {:error, reason}) returns {:error, ...}
  - IDN domain is encoded correctly (assert the URL passed to the stub contains punycode)

Write equivalent cases for Version.run/2:
  - 200 with JSON body containing the field returns {:ok, deployment} with current_version set
  - 200 with JSON body missing the field returns {:error, :missing_version_field, deployment}
  - 200 with plain text body returns {:ok, deployment} with current_version set to trimmed text
  - Non-200 status returns {:error, ...}
  - version_check_enabled false returns {:skipped, deployment} without making any HTTP call

---

## Task 9 — Warn on missing notifier token at startup

Commit message: fix: log warning when NOTIFIER_INTERNAL_SERVICE_TOKEN is blank in non-dev env

In lib/service_hub/application.ex, in the start/2 function, after the children list and
before Supervisor.start_link, add:

  if Mix.env() not in [:dev, :test] do
    token = Application.get_env(:service_hub, :notifier_internal_service_token, "")
    if is_binary(token) and String.trim(token) == "" do
      require Logger
      Logger.warning("NOTIFIER_INTERNAL_SERVICE_TOKEN is not set. Notification delivery will fail.")
    end
  end

Note: Mix.env() is not available at runtime in releases. Use config_env() from Config
instead, or check the env via an application env flag set in config/prod.exs. The cleanest
approach is to add to config/prod.exs:

  config :service_hub, :env, :prod

And in application.ex read Application.get_env(:service_hub, :env, :dev) for the check.

---

## Notes for Claude Code

- Run mix precommit after each task before committing.
- Tasks are ordered by risk: lower numbers are safer and have no dependencies.
- Tasks 6 and 7 depend on the existing test infrastructure being intact.
- Task 8 requires adding the http_client indirection before writing tests.
- Do not combine tasks into a single commit.
- If a task causes mix precommit to fail, fix the compilation or test error before
  moving to the next task.
