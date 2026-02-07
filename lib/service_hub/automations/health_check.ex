defmodule ServiceHub.Automations.HealthCheck do
  @moduledoc """
  Automation for running health checks on deployments.
  Wraps ServiceHub.Checks.Health with the automation interface.
  """
  @behaviour ServiceHub.Automations.Behaviour

  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Checks.Health
  alias ServiceHub.Checks.NotificationTrigger
  alias ServiceHub.Repo
  import Ecto.Query

  @impl true
  def id, do: "deployment_health"

  @impl true
  def targets_query do
    # Select deployments where automatic checks are enabled
    from d in Deployment,
      where: d.automatic_checks_enabled == true,
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
        # Run the health check
        result = Health.run(deployment, deployment.service)

        # Trigger notifications based on result
        trigger_health_notification(deployment, result)

        # Return automation result
        case result do
          {:ok, _updated_deployment} ->
            {:ok, "Health check passed"}

          {:warning, reason, _updated_deployment} ->
            {:warning, "Health check warning: #{inspect(reason)}"}

          {:error, reason, _updated_deployment} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def timeout_seconds, do: 15

  @impl true
  def max_failures, do: 3

  @impl true
  def concurrency_limit, do: 20

  # Private Functions

  defp trigger_health_notification(deployment, result) do
    NotificationTrigger.trigger_health_notification(deployment, result, "automatic")
  end
end
