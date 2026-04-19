defmodule ServiceHub.Checks.HealthTest do
  use ServiceHub.DataCase, async: false

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

    deployment =
      Repo.insert!(%Deployment{
        service_id: service.id,
        name: "test-deployment",
        host: "example.com",
        env: "production",
        automatic_checks_enabled: true,
        check_interval_minutes: 30,
        healthcheck_expectation: %{"allowed_statuses" => [200]}
      })

    %{service: service, deployment: deployment}
  end

  describe "run/2" do
    test "200 with matching expected_json returns {:ok, deployment}", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 200, body: %{"status" => "up"}}}
      })

      deployment =
        Repo.update!(
          Ecto.Changeset.change(deployment, %{
            healthcheck_expectation: %{
              "allowed_statuses" => [200],
              "expected_json" => %{"status" => "up"}
            }
          })
        )

      assert {:ok, updated} = Health.run(deployment, service)
      assert updated.last_health_status == "ok"
    end

    test "200 with non-matching expected_json returns {:warning, ...}", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 200, body: %{"status" => "degraded"}}}
      })

      deployment =
        Repo.update!(
          Ecto.Changeset.change(deployment, %{
            healthcheck_expectation: %{
              "allowed_statuses" => [200],
              "expected_json" => %{"status" => "up"}
            }
          })
        )

      assert {:warning, _reason, updated} = Health.run(deployment, service)
      assert updated.last_health_status == "warning"
    end

    test "500 response returns {:error, ...} with last_health_status down", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 500, body: "Internal Server Error"}}
      })

      assert {:error, _reason, updated} = Health.run(deployment, service)
      assert updated.last_health_status == "down"
    end

    test "404 response returns {:warning, ...} with last_health_status warning", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 404, body: "Not Found"}}
      })

      assert {:warning, _reason, updated} = Health.run(deployment, service)
      assert updated.last_health_status == "warning"
    end

    test "network error returns {:error, ...}", %{service: service, deployment: deployment} do
      Process.put(:http_responses, %{
        "example.com" => {:error, :econnrefused}
      })

      assert {:error, _reason, updated} = Health.run(deployment, service)
      assert updated.last_health_status == "down"
    end

    test "IDN domain is punycode-encoded in the request URL", %{service: service} do
      Process.put(:http_responses, %{
        "xn--caf-dma.example.com" => {:ok, %{status: 200, body: %{}}}
      })

      deployment =
        Repo.insert!(%Deployment{
          service_id: service.id,
          name: "idn-deployment",
          host: "café.example.com",
          env: "production",
          automatic_checks_enabled: true,
          check_interval_minutes: 30,
          healthcheck_expectation: %{"allowed_statuses" => [200]}
        })

      Health.run(deployment, service)

      last_url = Process.get(:http_last_url)
      assert String.contains?(last_url, "xn--caf-dma.example.com")
      refute String.contains?(last_url, "é")
    end
  end
end
