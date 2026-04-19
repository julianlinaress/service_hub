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
      {Oban, Application.fetch_env!(:service_hub, Oban)},
      {Phoenix.PubSub, name: ServiceHub.PubSub},
      # Start to serve requests, typically the last entry
      ServiceHubWeb.Endpoint
    ]

    if Application.get_env(:service_hub, :env, :dev) not in [:dev, :test] do
      token = Application.get_env(:service_hub, :notifier_internal_service_token, "")

      if is_binary(token) and String.trim(token) == "" do
        require Logger

        Logger.warning(
          "NOTIFIER_INTERNAL_SERVICE_TOKEN is not set. Notification delivery will fail."
        )
      end
    end

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
