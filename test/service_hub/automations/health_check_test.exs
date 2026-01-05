defmodule ServiceHub.Automations.HealthCheckTest do
  use ServiceHub.DataCase

  alias ServiceHub.Automations.HealthCheck
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  describe "HealthCheck automation" do
    test "id returns deployment_health" do
      assert HealthCheck.id() == "deployment_health"
    end

    test "timeout_seconds returns 15" do
      assert HealthCheck.timeout_seconds() == 15
    end

    test "max_failures returns 3" do
      assert HealthCheck.max_failures() == 3
    end

    test "concurrency_limit returns 20" do
      assert HealthCheck.concurrency_limit() == 20
    end

    test "targets_query returns deployments with automatic_checks_enabled" do
      # Create test data using fixtures
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      service = Repo.insert!(%Service{
        name: "Test Service",
        provider_id: provider.id,
        owner: "test",
        repo: "repo",
        healthcheck_endpoint_template: "https://{{host}}/health"
      })

      enabled_deployment = Repo.insert!(%Deployment{
        service_id: service.id,
        name: "enabled",
        host: "enabled.example.com",
        env: "test",
        automatic_checks_enabled: true,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

      disabled_deployment = Repo.insert!(%Deployment{
        service_id: service.id,
        name: "disabled",
        host: "disabled.example.com",
        env: "test",
        automatic_checks_enabled: false,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

      # Execute query
      query = HealthCheck.targets_query()
      ids = Repo.all(query)

      # Should only return enabled deployment
      assert enabled_deployment.id in ids
      refute disabled_deployment.id in ids
    end

    test "run returns error when deployment not found" do
      target = %{target_id: 99999}
      result = HealthCheck.run(target)

      assert {:error, :deployment_not_found} = result
    end
  end
end
