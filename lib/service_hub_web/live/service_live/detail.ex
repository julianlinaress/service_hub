defmodule ServiceHubWeb.ServiceLive.Detail do
  @moduledoc """
  Service detail view - create/edit service with dedicated page.
  """
  use ServiceHubWeb, :live_view

  alias ServiceHub.{Providers, Services}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header with back button --%>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/providers/#{@provider.id}"} class="btn btn-ghost btn-sm btn-square">
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>
          <div>
            <h1 class="text-2xl font-bold">{@page_title}</h1>
            <p class="text-sm text-base-content/60">{@provider.name}</p>
          </div>
        </div>

        <%!-- Form --%>
        <.live_component
          module={ServiceHubWeb.ServiceLive.FormComponent}
          id="service-form"
          action={@live_action}
          provider={@provider}
          service={@service}
          return_to={~p"/providers/#{@provider}"}
          current_scope={@current_scope}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"provider_id" => provider_id} = params, _session, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, provider_id)

    {:ok,
     socket
     |> assign(:provider, provider)
     |> assign(:service, load_service(socket, params))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if provider_validated?(socket.assigns.provider) do
      socket
      |> assign(:page_title, "New Service")
      |> assign(:service, %Services.Service{provider_id: socket.assigns.provider.id})
    else
      socket
      |> put_flash(:error, "Validate the provider before adding services")
      |> push_navigate(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if provider_validated?(socket.assigns.provider) do
      service = Services.get_service!(socket.assigns.current_scope, id)

      socket
      |> assign(:page_title, "Edit Service")
      |> assign(:service, service)
    else
      socket
      |> put_flash(:error, "Validate the provider before editing services")
      |> push_navigate(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp load_service(socket, %{"id" => id}) do
    Services.get_service!(socket.assigns.current_scope, id)
  end

  defp load_service(_socket, _params) do
    %Services.Service{}
  end

  defp provider_validated?(provider) do
    provider.last_validation_status == "ok"
  end
end
