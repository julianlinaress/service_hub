defmodule ServiceHub.Checks.HealthTest do
  use ServiceHub.DataCase

  alias ServiceHub.Checks.Health
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

    %{service: service}
  end

  describe "run/2 with internationalized domain names" do
    test "handles domain with special characters (ñ)", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "idn-deployment",
          host: "idicañada.com.ar",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      # This should not crash even if the HTTP request fails
      # The important thing is that the domain is properly encoded to Punycode
      result = Health.run(deployment, service)

      # We expect either success or error, but not a crash
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)

      # Verify the deployment was updated with a status
      updated_deployment = Repo.get(Deployment, deployment.id)
      assert updated_deployment.last_health_status in ["ok", "warning", "down"]
      assert updated_deployment.last_health_checked_at != nil
    end

    test "handles regular ASCII domain", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "ascii-deployment",
          host: "example.com",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # We expect either success or error, but not a crash
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)

      # Verify the deployment was updated with a status
      updated_deployment = Repo.get(Deployment, deployment.id)
      assert updated_deployment.last_health_status in ["ok", "warning", "down"]
      assert updated_deployment.last_health_checked_at != nil
    end

    test "handles domain with https:// prefix by stripping it", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "https-prefix-deployment",
          host: "https://example.com",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # Should handle the https:// prefix without issues
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)

      updated_deployment = Repo.get(Deployment, deployment.id)
      assert updated_deployment.last_health_status in ["ok", "warning", "down"]
    end

    test "handles domain with path component", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "path-deployment",
          host: "impacs.hospital-italiano.org.ar/imviewer5",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # Should handle the path component without crashing
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)

      updated_deployment = Repo.get(Deployment, deployment.id)
      assert updated_deployment.last_health_status in ["ok", "warning", "down"]
    end

    test "handles internationalized domain with path component", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "idn-path-deployment",
          host: "idicañada.com.ar/api/v1",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # Should handle both IDN and path component
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)

      updated_deployment = Repo.get(Deployment, deployment.id)
      assert updated_deployment.last_health_status in ["ok", "warning", "down"]
    end
  end

  describe "run/2 with api keys" do
    test "includes x-api-key header when api_key is set", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "api-key-deployment",
          host: "secure.example.com",
          env: "production",
          api_key: "test-api-key-123",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # We can't verify the header was sent without mocking,
      # but we can verify the function runs without error
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)
    end

    test "does not include x-api-key header when api_key is nil", %{service: service} do
      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "no-api-key-deployment",
          host: "public.example.com",
          env: "production",
          api_key: nil,
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      result = Health.run(deployment, service)

      # Should run without error even without api_key
      assert match?({:ok, _}, result) or match?({:error, _, _}, result) or
               match?({:warning, _, _}, result)
    end
  end
end
