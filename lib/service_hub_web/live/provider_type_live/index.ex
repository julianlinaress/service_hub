defmodule ServiceHubWeb.ProviderTypeLive.Index do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Provider types
        <:actions>
          <.button variant="primary" navigate={~p"/provider_types/new"}>
            <.icon name="hero-plus" /> New Provider type
          </.button>
        </:actions>
      </.header>

      <.table
        id="provider_types"
        rows={@streams.provider_types}
        row_click={fn {_id, provider_type} -> JS.navigate(~p"/provider_types/#{provider_type}") end}
      >
        <:col :let={{_id, provider_type}} label="Name">{provider_type.name}</:col>
        <:col :let={{_id, provider_type}} label="Key">{provider_type.key}</:col>
        <:col :let={{_id, provider_type}} label="Required fields">
          {format_fields(provider_type.required_fields)}
        </:col>
        <:action :let={{_id, provider_type}}>
          <div class="sr-only">
            <.link navigate={~p"/provider_types/#{provider_type}"}>Show</.link>
          </div>
          <.link navigate={~p"/provider_types/#{provider_type}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, provider_type}}>
          <.link
            phx-click={JS.push("delete", value: %{id: provider_type.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_provider_types(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Provider types")
     |> stream(:provider_types, list_provider_types(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    provider_type = Providers.get_provider_type!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_provider_type(socket.assigns.current_scope, provider_type)

    {:noreply, stream_delete(socket, :provider_types, provider_type)}
  end

  @impl true
  def handle_info({type, %ServiceHub.Providers.ProviderType{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :provider_types, list_provider_types(socket.assigns.current_scope),
       reset: true
     )}
  end

  defp list_provider_types(current_scope) do
    Providers.list_provider_types(current_scope)
  end

  defp format_fields(fields) when is_map(fields) and map_size(fields) > 0,
    do: Jason.encode!(fields)

  defp format_fields(_), do: ""
end
