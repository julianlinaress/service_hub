defmodule ServiceHub.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ServiceHubWeb.Telemetry,
      ServiceHub.Repo,
      {DNSCluster, query: Application.get_env(:service_hub, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ServiceHub.PubSub},
      # Task supervisor for automation runners
      {Task.Supervisor, name: ServiceHub.TaskSupervisor},
      # Automation scheduler
      {ServiceHub.Automations.Scheduler, []},
      # Start to serve requests, typically the last entry
      ServiceHubWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ServiceHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ServiceHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
