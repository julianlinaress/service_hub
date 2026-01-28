defmodule ServiceHub.Checks.NotificationTriggerTest do
  use ServiceHub.DataCase

  alias ServiceHub.Checks.NotificationTrigger
  alias ServiceHub.Notifications.DeploymentNotificationState
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service

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

    deployment =
      Repo.insert!(%Deployment{
        service_id: service.id,
        name: "test-deployment",
        host: "test.example.com",
        env: "production",
        automatic_checks_enabled: true,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

    %{deployment: deployment, service: service}
  end

  describe "trigger_health_notification/3" do
    test "creates initial state record on first check with ok status", %{deployment: deployment} do
      result = {:ok, deployment}

      NotificationTrigger.trigger_health_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      assert state != nil
      assert state.last_status == "ok"
      assert state.last_notified_at != nil
    end

    test "creates initial state record on first check with warning status", %{
      deployment: deployment
    } do
      result = {:warning, {:unexpected_status, 404}, deployment}

      NotificationTrigger.trigger_health_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      assert state != nil
      assert state.last_status == "warning"
      assert state.last_notified_at != nil
    end

    test "creates initial state record on first check with down status", %{deployment: deployment} do
      result = {:error, {:unexpected_status, 500}, deployment}

      NotificationTrigger.trigger_health_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      assert state != nil
      assert state.last_status == "down"
      assert state.last_notified_at != nil
    end

    test "does not notify when status unchanged", %{deployment: deployment} do
      # First check - creates state with "ok"
      result1 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      first_notified_at = state1.last_notified_at

      # Wait a moment to ensure timestamp would change if updated
      :timer.sleep(10)

      # Second check - same status
      result2 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      # Status updated but last_notified_at should not change (no notification)
      assert state2.last_status == "ok"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :eq
    end

    test "notifies on status change from ok to warning", %{deployment: deployment} do
      # First check - ok
      result1 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      first_notified_at = state1.last_notified_at

      # Wait to ensure timestamp changes
      :timer.sleep(10)

      # Second check - warning
      result2 = {:warning, {:unexpected_status, 404}, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      # Should notify - last_notified_at should be updated
      assert state2.last_status == "warning"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :gt
    end

    test "notifies on status change from ok to down", %{deployment: deployment} do
      # First check - ok
      result1 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      first_notified_at = state1.last_notified_at

      # Wait to ensure timestamp changes
      :timer.sleep(10)

      # Second check - down
      result2 = {:error, {:unexpected_status, 500}, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      # Should notify - last_notified_at should be updated
      assert state2.last_status == "down"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :gt
    end

    test "notifies on recovery from down to ok", %{deployment: deployment} do
      # First check - down
      result1 = {:error, {:unexpected_status, 500}, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      first_notified_at = state1.last_notified_at

      # Wait to ensure timestamp changes
      :timer.sleep(10)

      # Second check - recovered
      result2 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      # Should notify recovery - last_notified_at should be updated
      assert state2.last_status == "ok"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :gt
    end

    test "notifies on recovery from warning to ok", %{deployment: deployment} do
      # First check - warning
      result1 = {:warning, {:unexpected_status, 404}, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      first_notified_at = state1.last_notified_at

      # Wait to ensure timestamp changes
      :timer.sleep(10)

      # Second check - recovered
      result2 = {:ok, deployment}
      NotificationTrigger.trigger_health_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      # Should notify recovery - last_notified_at should be updated
      assert state2.last_status == "ok"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :gt
    end

    test "uses automatic source tag when specified", %{deployment: deployment} do
      result = {:ok, deployment}

      # This test verifies the function runs without error with "automatic" source
      # In a real scenario, we'd verify the FYI event has the correct tag
      NotificationTrigger.trigger_health_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      assert state != nil
    end

    test "uses manual source tag when specified", %{deployment: deployment} do
      result = {:ok, deployment}

      # This test verifies the function runs without error with "manual" source
      # In a real scenario, we'd verify the FYI event has the correct tag
      NotificationTrigger.trigger_health_notification(deployment, result, "manual")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "health"
        )

      assert state != nil
    end
  end

  describe "trigger_version_notification/3" do
    test "creates initial state record on first version detection", %{deployment: deployment} do
      updated_deployment = %{deployment | current_version: "1.0.0"}
      result = {:ok, updated_deployment}

      NotificationTrigger.trigger_version_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      assert state != nil
      assert state.last_version == "1.0.0"
      assert state.last_notified_at != nil
    end

    test "does not notify when version unchanged", %{deployment: deployment} do
      # First check - version 1.0.0
      updated_deployment1 = %{deployment | current_version: "1.0.0"}
      result1 = {:ok, updated_deployment1}
      NotificationTrigger.trigger_version_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      first_notified_at = state1.last_notified_at

      # Wait a moment
      :timer.sleep(10)

      # Second check - same version
      updated_deployment2 = %{deployment | current_version: "1.0.0"}
      result2 = {:ok, updated_deployment2}
      NotificationTrigger.trigger_version_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      # Version tracked but no notification (last_notified_at unchanged)
      assert state2.last_version == "1.0.0"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :eq
    end

    test "notifies when version changes", %{deployment: deployment} do
      # First check - version 1.0.0
      updated_deployment1 = %{deployment | current_version: "1.0.0"}
      result1 = {:ok, updated_deployment1}
      NotificationTrigger.trigger_version_notification(deployment, result1, "automatic")

      state1 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      first_notified_at = state1.last_notified_at

      # Wait to ensure timestamp changes
      :timer.sleep(10)

      # Second check - new version
      updated_deployment2 = %{deployment | current_version: "1.1.0"}
      result2 = {:ok, updated_deployment2}
      NotificationTrigger.trigger_version_notification(deployment, result2, "automatic")

      state2 =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      # Should notify - both version and last_notified_at updated
      assert state2.last_version == "1.1.0"
      assert DateTime.compare(state2.last_notified_at, first_notified_at) == :gt
    end

    test "does not notify on skipped checks", %{deployment: deployment} do
      updated_deployment = %{deployment | current_version: "1.0.0"}
      result = {:skipped, updated_deployment}

      NotificationTrigger.trigger_version_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      # State may be created but no notification sent (last_notified_at is nil or not set)
      if state do
        assert state.last_notified_at == nil
      end
    end

    test "notifies on version check errors", %{deployment: deployment} do
      updated_deployment = %{deployment | current_version: nil}
      result = {:error, :connection_failed, updated_deployment}

      NotificationTrigger.trigger_version_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      # Should create state and notify on error
      assert state != nil
      assert state.last_notified_at != nil
    end

    test "uses automatic source tag when specified", %{deployment: deployment} do
      updated_deployment = %{deployment | current_version: "1.0.0"}
      result = {:ok, updated_deployment}

      NotificationTrigger.trigger_version_notification(deployment, result, "automatic")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      assert state != nil
    end

    test "uses manual source tag when specified", %{deployment: deployment} do
      updated_deployment = %{deployment | current_version: "1.0.0"}
      result = {:ok, updated_deployment}

      NotificationTrigger.trigger_version_notification(deployment, result, "manual")

      state =
        Repo.get_by(DeploymentNotificationState,
          deployment_id: deployment.id,
          check_type: "version"
        )

      assert state != nil
    end
  end
end
