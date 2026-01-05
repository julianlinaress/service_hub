defmodule ServiceHub.Automations.VersionCheck do
  @moduledoc """
  Automation for running version checks on deployments.
  Wraps ServiceHub.Checks.Version with the automation interface.
  """
  @behaviour ServiceHub.Automations.Behaviour

  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Checks.Version
  alias ServiceHub.Repo
  import Ecto.Query

  @impl true
  def id, do: "deployment_version"

  @impl true
  def targets_query do
    # Select deployments where automatic checks AND version checks are enabled
    from d in Deployment,
      where: d.automatic_checks_enabled == true,
      where: d.version_check_enabled == true,
      select: d.id
  end

  @impl true
  def run(%{target_id: deployment_id}) do
    # Load the deployment with service preloaded
    deployment =
      Repo.get(Deployment, deployment_id)
      |> Repo.preload(service: :provider)

    case deployment do
      nil ->
        {:error, :deployment_not_found}

      %Deployment{} = deployment ->
        # Run the version check
        case Version.run(deployment, deployment.service) do
          {:ok, _updated_deployment} ->
            {:ok, "Version check passed"}

          {:skipped, _updated_deployment} ->
            {:ok, "Version check skipped (disabled)"}

          {:error, reason, _updated_deployment} ->
            # Version check failures are logged but not critical
            {:warning, "Version check failed: #{inspect(reason)}"}
        end
    end
  end

  @impl true
  def timeout_seconds, do: 15

  @impl true
  def max_failures, do: 5

  @impl true
  def concurrency_limit, do: 10
end
