defmodule ServiceHub.DeploymentsSyncTest do
  use ServiceHub.DataCase

  alias ServiceHub.Deployments
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Automations.AutomationTarget
  alias ServiceHub.Services.Service

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  describe "sync_automation_targets/1" do
    setup do
      # Create test provider and service using fixtures
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      service =
        Repo.insert!(%Service{
          name: "Test Service",
          provider_id: provider.id,
          owner: "test",
          repo: "repo",
          healthcheck_endpoint_template: "https://{{host}}/health",
          version_endpoint_template: "https://{{host}}/version"
        })

      %{service: service}
    end

    test "creates health check target when automatic checks enabled", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      Deployments.sync_automation_targets(deployment)

      # Should create health check target
      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      assert health_target != nil
      assert health_target.enabled == true
      assert health_target.interval_minutes == 30
    end

    test "creates both targets when automatic and version checks enabled", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          version_check_enabled: true,
          check_interval_minutes: 60,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      Deployments.sync_automation_targets(deployment)

      # Should create both targets
      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      version_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_version" and
                at.target_id == ^deployment.id
        )

      assert health_target != nil
      assert version_target != nil
      assert health_target.interval_minutes == 60
      assert version_target.interval_minutes == 60
    end

    test "updates existing target when sync called again", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # First sync
      Deployments.sync_automation_targets(deployment)

      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      future_next_run = DateTime.add(DateTime.utc_now(:microsecond), 1, :day)

      {:ok, _} =
        health_target
        |> AutomationTarget.changeset(%{next_run_at: future_next_run})
        |> Repo.update()

      # Update deployment interval
      {:ok, deployment} =
        deployment
        |> Deployment.changeset(%{check_interval_minutes: 60})
        |> Repo.update()

      # Sync again
      Deployments.sync_automation_targets(deployment)

      # Should update existing target
      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      assert health_target.interval_minutes == 60
      assert DateTime.compare(health_target.next_run_at, future_next_run) == :lt

      # Should only have one target (not create duplicate)
      target_count =
        Repo.aggregate(
          from(at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
          ),
          :count
        )

      assert target_count == 1
    end

    test "re-enables target and resets next_run_at when previously disabled", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # First sync
      Deployments.sync_automation_targets(deployment)

      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      far_future = DateTime.add(DateTime.utc_now(:microsecond), 1, :day)

      {:ok, _} =
        health_target
        |> AutomationTarget.changeset(%{enabled: false, next_run_at: far_future})
        |> Repo.update()

      now = DateTime.utc_now(:second)

      # Sync again
      Deployments.sync_automation_targets(deployment)

      updated =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      assert updated.enabled == true
      assert DateTime.diff(updated.next_run_at, now, :second) <= 5
      assert DateTime.diff(updated.next_run_at, now, :second) >= -5
    end

    test "removes targets when automatic checks disabled", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          version_check_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # Create targets
      Deployments.sync_automation_targets(deployment)

      # Disable automatic checks
      {:ok, deployment} =
        deployment
        |> Deployment.changeset(%{automatic_checks_enabled: false})
        |> Repo.update()

      # Sync again
      Deployments.sync_automation_targets(deployment)

      # Should remove all targets
      target_count =
        Repo.aggregate(
          from(at in AutomationTarget, where: at.target_id == ^deployment.id),
          :count
        )

      assert target_count == 0
    end

    test "removes version target when version checks disabled but keeps health", %{
      service: service
    } do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          version_check_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # Create both targets
      Deployments.sync_automation_targets(deployment)

      # Disable version checks only
      {:ok, deployment} =
        deployment
        |> Deployment.changeset(%{version_check_enabled: false})
        |> Repo.update()

      # Sync again
      Deployments.sync_automation_targets(deployment)

      # Health target should still exist
      health_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_health" and
                at.target_id == ^deployment.id
        )

      assert health_target != nil

      # Version target should be removed
      version_target =
        Repo.one(
          from at in AutomationTarget,
            where:
              at.automation_id == "deployment_version" and
                at.target_id == ^deployment.id
        )

      assert version_target == nil
    end
  end

  describe "delete_automation_targets/1" do
    setup do
      # Create test data using fixtures
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      service =
        Repo.insert!(%Service{
          name: "Test Service",
          provider_id: provider.id,
          owner: "test",
          repo: "repo"
        })

      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "test",
          host: "test.example.com",
          env: "test",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # Create automation targets
      Deployments.sync_automation_targets(deployment)

      %{deployment: deployment}
    end

    test "removes all automation targets for deployment", %{deployment: deployment} do
      # Verify targets exist
      initial_count =
        Repo.aggregate(
          from(at in AutomationTarget, where: at.target_id == ^deployment.id),
          :count
        )

      assert initial_count > 0

      # Delete targets
      Deployments.delete_automation_targets(deployment)

      # Verify targets removed
      final_count =
        Repo.aggregate(
          from(at in AutomationTarget, where: at.target_id == ^deployment.id),
          :count
        )

      assert final_count == 0
    end
  end
end
