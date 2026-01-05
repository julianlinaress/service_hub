defmodule ServiceHub.Deployments.PubSub do
  @moduledoc """
  PubSub utilities for broadcasting deployment check updates.

  Topics:
  - "deployment:<id>" - Updates for a specific deployment
  - "service:<id>:deployments" - All deployments for a service
  """

  alias Phoenix.PubSub
  alias ServiceHub.Deployments.Deployment

  @pubsub ServiceHub.PubSub

  @doc """
  Broadcasts when a deployment check completes (health or version).
  """
  def broadcast_check_completed(%Deployment{} = deployment, check_type) do
    deployment = ServiceHub.Repo.preload(deployment, :service)

    payload = %{
      deployment_id: deployment.id,
      service_id: deployment.service_id,
      check_type: check_type,
      last_health_status: deployment.last_health_status,
      last_health_checked_at: deployment.last_health_checked_at,
      current_version: deployment.current_version,
      last_version_checked_at: deployment.last_version_checked_at
    }

    # Broadcast to deployment-specific topic
    PubSub.broadcast(@pubsub, "deployment:#{deployment.id}", {:check_completed, payload})

    # Broadcast to service-wide topic
    PubSub.broadcast(
      @pubsub,
      "service:#{deployment.service_id}:deployments",
      {:check_completed, payload}
    )
  end

  @doc """
  Subscribes to updates for a specific deployment.
  """
  def subscribe_deployment(deployment_id) do
    PubSub.subscribe(@pubsub, "deployment:#{deployment_id}")
  end

  @doc """
  Subscribes to all deployment updates for a service.
  """
  def subscribe_service_deployments(service_id) do
    PubSub.subscribe(@pubsub, "service:#{service_id}:deployments")
  end

  @doc """
  Unsubscribes from deployment updates.
  """
  def unsubscribe_deployment(deployment_id) do
    PubSub.unsubscribe(@pubsub, "deployment:#{deployment_id}")
  end

  @doc """
  Unsubscribes from service deployment updates.
  """
  def unsubscribe_service_deployments(service_id) do
    PubSub.unsubscribe(@pubsub, "service:#{service_id}:deployments")
  end
end
