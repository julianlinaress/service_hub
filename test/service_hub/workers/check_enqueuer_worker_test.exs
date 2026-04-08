defmodule ServiceHub.Workers.CheckEnqueuerWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  alias ServiceHub.Automations.AutomationTarget
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service
  alias ServiceHub.Workers.{CheckEnqueuerWorker, HealthCheckWorker, VersionCheckWorker}

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  setup do
    scope = user_scope_fixture()
    provider = provider_fixture(scope)

    service =
      Repo.insert!(%Service{
        name: "Test Service",
        provider_id: provider.id,
        owner: "test",
        repo: "repo",
        healthcheck_endpoint_template: "https://{{host}}/health"
      })

    %{service: service}
  end

  describe "perform/1" do
    test "enqueues health check jobs for due targets", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 5,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      past = DateTime.add(DateTime.utc_now(), -120, :second)

      Repo.insert!(
        AutomationTarget.changeset(%AutomationTarget{}, %{
          automation_id: "deployment_health",
          target_type: "deployment",
          target_id: deployment.id,
          enabled: true,
          interval_minutes: 5,
          next_run_at: past,
          consecutive_failures: 0
        })
      )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      assert_enqueued(worker: HealthCheckWorker, args: %{target_id: deployment.id})
    end

    test "enqueues version check jobs for due targets", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test-v",
          host: "test-v.example.com",
          env: "test",
          automatic_checks_enabled: true,
          version_check_enabled: true,
          check_interval_minutes: 5,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      past = DateTime.add(DateTime.utc_now(), -120, :second)

      Repo.insert!(
        AutomationTarget.changeset(%AutomationTarget{}, %{
          automation_id: "deployment_version",
          target_type: "deployment",
          target_id: deployment.id,
          enabled: true,
          interval_minutes: 5,
          next_run_at: past,
          consecutive_failures: 0
        })
      )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      assert_enqueued(worker: VersionCheckWorker, args: %{target_id: deployment.id})
    end

    test "skips paused targets", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "paused",
          host: "paused.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 5,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      past = DateTime.add(DateTime.utc_now(), -120, :second)

      Repo.insert!(
        AutomationTarget.changeset(%AutomationTarget{}, %{
          automation_id: "deployment_health",
          target_type: "deployment",
          target_id: deployment.id,
          enabled: true,
          interval_minutes: 5,
          next_run_at: past,
          paused_at: DateTime.utc_now(:microsecond),
          consecutive_failures: 3
        })
      )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      refute_enqueued(worker: HealthCheckWorker, args: %{target_id: deployment.id})
    end

    test "skips targets not yet due", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "not-due",
          host: "not-due.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 5,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      Repo.insert!(
        AutomationTarget.changeset(%AutomationTarget{}, %{
          automation_id: "deployment_health",
          target_type: "deployment",
          target_id: deployment.id,
          enabled: true,
          interval_minutes: 5,
          next_run_at: future,
          consecutive_failures: 0
        })
      )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      refute_enqueued(worker: HealthCheckWorker, args: %{target_id: deployment.id})
    end

    test "sets running_at on enqueued targets", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "running",
          host: "running.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 5,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      past = DateTime.add(DateTime.utc_now(), -120, :second)

      target =
        Repo.insert!(
          AutomationTarget.changeset(%AutomationTarget{}, %{
            automation_id: "deployment_health",
            target_type: "deployment",
            target_id: deployment.id,
            enabled: true,
            interval_minutes: 5,
            next_run_at: past,
            consecutive_failures: 0
          })
        )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.running_at != nil
    end

    test "clears stale leases older than 10 minutes" do
      stale_time = DateTime.add(DateTime.utc_now(), -15 * 60, :second)

      target =
        Repo.insert!(
          AutomationTarget.changeset(%AutomationTarget{}, %{
            automation_id: "deployment_health",
            target_type: "deployment",
            target_id: 88888,
            enabled: true,
            interval_minutes: 5,
            running_at: stale_time,
            next_run_at: DateTime.utc_now(:microsecond),
            consecutive_failures: 0
          })
        )

      assert :ok = perform_job(CheckEnqueuerWorker, %{})

      updated = Repo.get!(AutomationTarget, target.id)
      assert is_nil(updated.running_at)
    end
  end
end
