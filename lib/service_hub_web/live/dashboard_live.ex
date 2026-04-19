defmodule ServiceHubWeb.DashboardLive do
  @moduledoc """
  Main dashboard view - overview of all providers, services, and installations.
  """
  use ServiceHubWeb, :live_view

  alias ServiceHub.{Providers, Services, Deployments}
  alias ServiceHubWeb.Components.ProviderIcon
  alias ServiceHubWeb.Components.Status.HealthBadge

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold">Dashboard</h1>
        </div>

        <%!-- Providers Grid --%>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold">Providers</h2>
            <.link navigate={~p"/config/providers/new"} class="btn btn-ghost btn-sm">
              <.icon name="hero-plus" class="w-4 h-4" /> New
            </.link>
          </div>

          <div :if={Enum.empty?(@providers)} class="text-center py-8 text-sm text-base-content/50">
            No providers configured
          </div>

          <div
            :if={!Enum.empty?(@providers)}
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3"
          >
            <.provider_card :for={provider <- @providers} provider={provider} />
          </div>
        </div>

        <%!-- Recent Activity --%>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold">Recent Health Checks</h2>
            <span class="btn btn-ghost btn-sm pointer-events-none opacity-60" aria-disabled="true">
              View all <.icon name="hero-arrow-right" class="w-4 h-4" />
            </span>
          </div>

          <div
            :if={Enum.empty?(@recent_deployments)}
            class="text-center py-8 text-sm text-base-content/50"
          >
            No service installations yet
          </div>

          <div :if={!Enum.empty?(@recent_deployments)} class="space-y-2">
            <div
              :for={deployment <- @recent_deployments}
              class="flex items-center justify-between p-3 rounded hover:bg-base-200"
            >
              <div class="flex items-center gap-4 flex-1">
                <div>
                  <div class="font-medium">{deployment.name}</div>
                  <div class="text-sm text-base-content/50">{deployment.env}</div>
                </div>
              </div>
              <div class="flex items-center gap-4">
                <code class="text-xs font-mono text-base-content/50">
                  {deployment.current_version || "—"}
                </code>
                <HealthBadge.health_badge
                  status={deployment.last_health_status || "unknown"}
                  size="sm"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :provider, :map, required: true

  defp provider_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/providers/#{@provider.id}"}
      class="flex items-center justify-between p-4 rounded border border-base-300 hover:border-base-content/20 hover:bg-base-200 transition-colors group"
    >
      <div class="flex items-center gap-3 flex-1 min-w-0">
        <ProviderIcon.provider_icon type={provider_key(@provider)} size="md" />
        <div class="flex-1 min-w-0">
          <div class="font-medium truncate">{@provider.name}</div>
          <div class="text-sm text-base-content/50 truncate">{@provider.base_url}</div>
        </div>
      </div>
      <.icon
        name="hero-chevron-right"
        class="w-5 h-5 text-base-content/30 group-hover:text-base-content/60 transition-colors flex-shrink-0"
      />
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_providers(socket.assigns.current_scope)
    end

    providers = load_providers(socket.assigns.current_scope)
    deployments = Deployments.list_recent_deployments(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:providers, providers)
     |> assign(:recent_deployments, deployments)}
  end

  @impl true
  def handle_info({:provider_created, _provider}, socket) do
    providers = load_providers(socket.assigns.current_scope)
    {:noreply, assign(socket, :providers, providers)}
  end

  @impl true
  def handle_info({:provider_updated, provider}, socket) do
    providers =
      Enum.map(socket.assigns.providers, fn p ->
        if p.id == provider.id, do: provider, else: p
      end)

    {:noreply, assign(socket, :providers, providers)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_providers(scope) do
    Providers.list_providers(scope)
    |> Enum.map(fn provider ->
      services_count = Services.count_services_for_provider(scope, provider.id)
      Map.put(provider, :services_count, services_count)
    end)
  end

  defp provider_key(provider) do
    if provider.provider_type do
      provider.provider_type.key
    else
      "unknown"
    end
  end
end
