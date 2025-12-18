defmodule ServiceHubWeb.ProviderLive.Dashboard do
  @moduledoc """
  Provider dashboard view - shows provider status, services, and installations.
  """
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers
  alias ServiceHub.Services
  alias ServiceHubWeb.Components.ProviderIcon

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Provider Header --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm btn-square">
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
            <div class="flex items-center gap-3">
              <ProviderIcon.provider_icon type={provider_key(@provider)} size="lg" />
              <div>
                <h1 class="text-2xl font-bold">{@provider.name}</h1>
                <p class="text-sm text-base-content/50">{@provider.base_url}</p>
              </div>
            </div>
          </div>

          <div class="flex gap-2">
            <.button
              phx-click="validate-connection"
              variant="ghost"
              phx-disable-with="Validating..."
            >
              <.icon name="hero-arrow-path" class="w-4 h-4" />
              Validate
            </.button>
            <.button navigate={~p"/config/providers/#{@provider}/edit"} variant="ghost">
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
              Settings
            </.button>
          </div>
        </div>

        <%!-- Services Section --%>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold">Services</h2>
            <.button
              navigate={~p"/providers/#{@provider}/services/new"}
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-plus" class="w-4 h-4" />
              New
            </.button>
          </div>

          <div :if={Enum.empty?(@services)} class="text-center py-8 text-sm text-base-content/50">
            No services configured
          </div>

          <div :if={!Enum.empty?(@services)} class="space-y-2">
            <.service_card
              :for={service <- @services}
              service={service}
              provider={@provider}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :service, :map, required: true
  attr :provider, :map, required: true

  defp service_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/providers/#{@provider.id}/services/#{@service.id}"}
      class="flex items-center justify-between p-3 rounded hover:bg-base-200 transition-colors group"
    >
      <div class="flex items-center gap-3 flex-1 min-w-0">
        <div class="flex-1 min-w-0">
          <div class="font-medium truncate">{@service.name}</div>
          <div class="text-sm text-base-content/50 truncate">
            {@service.owner}/{@service.repo}
          </div>
        </div>
      </div>
      <.icon name="hero-chevron-right" class="w-5 h-5 text-base-content/30 group-hover:text-base-content/60 transition-colors flex-shrink-0" />
    </.link>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Providers.subscribe_providers(socket.assigns.current_scope)
      Services.subscribe_services(socket.assigns.current_scope, provider.id)
    end

    services = Services.list_services_for_provider(socket.assigns.current_scope, provider)

    {:ok,
     socket
     |> assign(:provider, provider)
     |> assign(:services, services)}
  end

  @impl true
  def handle_event("validate-connection", _params, socket) do
    case Providers.validate_provider_connection(socket.assigns.current_scope, socket.assigns.provider) do
      {:ok, updated_provider} ->
        {:noreply,
         socket
         |> assign(:provider, updated_provider)
         |> put_flash(:info, "Provider validated successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Validation failed: #{reason}")}
    end
  end

  @impl true
  def handle_info({:service_created, service}, socket) do
    if service.provider_id == socket.assigns.provider.id do
      services = Services.list_services_for_provider(socket.assigns.current_scope, socket.assigns.provider)
      {:noreply, assign(socket, :services, services)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:service_updated, service}, socket) do
    if service.provider_id == socket.assigns.provider.id do
      services =
        Enum.map(socket.assigns.services, fn s ->
          if s.id == service.id, do: service, else: s
        end)

      {:noreply, assign(socket, :services, services)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:provider_updated, provider}, socket) do
    if provider.id == socket.assigns.provider.id do
      {:noreply, assign(socket, :provider, provider)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp provider_key(provider) do
    if provider.provider_type do
      provider.provider_type.key
    else
      "unknown"
    end
  end
end
