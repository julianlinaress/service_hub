defmodule ServiceHub.Checks.VersionTest do
  use ServiceHub.DataCase, async: false

  alias ServiceHub.Checks.Version
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
        version_endpoint_template: "https://{{host}}/api/version"
      })

    deployment =
      Repo.insert!(%Deployment{
        service_id: service.id,
        name: "test-deployment",
        host: "example.com",
        env: "production",
        automatic_checks_enabled: true,
        check_interval_minutes: 30,
        version_check_enabled: true
      })

    %{service: service, deployment: deployment}
  end

  describe "run/2" do
    test "version_check_enabled false returns {:skipped, deployment} without HTTP call", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{})

      deployment = Repo.update!(Ecto.Changeset.change(deployment, version_check_enabled: false))

      assert {:skipped, updated} = Version.run(deployment, service)
      assert updated.id == deployment.id
      assert Process.get(:http_last_url) == nil
    end

    test "200 with JSON body containing version field returns {:ok, deployment} with current_version",
         %{service: service, deployment: deployment} do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 200, body: %{"version" => "1.2.3"}}}
      })

      assert {:ok, updated} = Version.run(deployment, service)
      assert updated.current_version == "1.2.3"
    end

    test "200 with JSON body missing the version field returns {:error, :missing_version_field, deployment}",
         %{service: service, deployment: deployment} do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 200, body: %{"other_field" => "value"}}}
      })

      assert {:error, :missing_version_field, _updated} = Version.run(deployment, service)
    end

    test "200 with plain text body returns {:ok, deployment} with trimmed version", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 200, body: "  v2.0.0\n"}}
      })

      assert {:ok, updated} = Version.run(deployment, service)
      assert updated.current_version == "v2.0.0"
    end

    test "non-200 status returns {:error, ...}", %{service: service, deployment: deployment} do
      Process.put(:http_responses, %{
        "example.com" => {:ok, %{status: 503, body: "Service Unavailable"}}
      })

      assert {:error, {:unexpected_status, 503}, _updated} = Version.run(deployment, service)
    end

    test "network error returns {:error, reason, deployment}", %{
      service: service,
      deployment: deployment
    } do
      Process.put(:http_responses, %{
        "example.com" => {:error, :econnrefused}
      })

      assert {:error, :econnrefused, _updated} = Version.run(deployment, service)
    end
  end
end
