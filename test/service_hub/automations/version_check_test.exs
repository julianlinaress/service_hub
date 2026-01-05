defmodule ServiceHub.Automations.VersionCheckTest do
  use ServiceHub.DataCase

  alias ServiceHub.Automations.VersionCheck
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service

  import ServiceHub.AccountsFixtures
  import ServiceHub.ProvidersFixtures

  describe "VersionCheck automation" do
    test "id returns deployment_version" do
      assert VersionCheck.id() == "deployment_version"
    end

    test "timeout_seconds returns 15" do
      assert VersionCheck.timeout_seconds() == 15
    end

    test "max_failures returns 5" do
      assert VersionCheck.max_failures() == 5
    end

    test "concurrency_limit returns 10" do
      assert VersionCheck.concurrency_limit() == 10
    end

    test "targets_query returns deployments with both automatic and version checks enabled" do
      # Create test data using fixtures
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      service = Repo.insert!(%Service{
        name: "Test Service",
        provider_id: provider.id,
        owner: "test",
        repo: "repo",
        version_endpoint_template: "https://{{host}}/version"
      })

      # Both checks enabled - should be included
      both_enabled = Repo.insert!(%Deployment{
        service_id: service.id,
        name: "both_enabled",
        host: "both.example.com",
        env: "test",
        automatic_checks_enabled: true,
        version_check_enabled: true,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

      # Only automatic enabled - should NOT be included
      _only_automatic = Repo.insert!(%Deployment{
        service_id: service.id,
        name: "only_automatic",
        host: "auto.example.com",
        env: "test",
        automatic_checks_enabled: true,
        version_check_enabled: false,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

      # Both disabled - should NOT be included
      _both_disabled = Repo.insert!(%Deployment{
        service_id: service.id,
        name: "both_disabled",
        host: "disabled.example.com",
        env: "test",
        automatic_checks_enabled: false,
        version_check_enabled: false,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

      # Execute query
      query = VersionCheck.targets_query()
      ids = Repo.all(query)

      # Should only return deployment with both checks enabled
      assert ids == [both_enabled.id]
    end

    test "run returns error when deployment not found" do
      target = %{target_id: 99999}
      result = VersionCheck.run(target)

      assert {:error, :deployment_not_found} = result
    end
  end
end
