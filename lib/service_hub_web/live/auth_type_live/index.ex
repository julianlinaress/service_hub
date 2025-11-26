defmodule ServiceHubWeb.AuthTypeLive.Index do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Auth types
        <:actions>
          <.button variant="primary" navigate={~p"/auth_types/new"}>
            <.icon name="hero-plus" /> New Auth type
          </.button>
        </:actions>
      </.header>

      <.table
        id="auth_types"
        rows={@streams.auth_types}
        row_click={fn {_id, auth_type} -> JS.navigate(~p"/auth_types/#{auth_type}") end}
      >
        <:col :let={{_id, auth_type}} label="Name">{auth_type.name}</:col>
        <:col :let={{_id, auth_type}} label="Key">{auth_type.key}</:col>
        <:col :let={{_id, auth_type}} label="Required fields">
          {format_fields(auth_type.required_fields)}
        </:col>
        <:action :let={{_id, auth_type}}>
          <div class="sr-only">
            <.link navigate={~p"/auth_types/#{auth_type}"}>Show</.link>
          </div>
          <.link navigate={~p"/auth_types/#{auth_type}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, auth_type}}>
          <.link
            phx-click={JS.push("delete", value: %{id: auth_type.id}) |> hide("##{id}")}
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
      Providers.subscribe_auth_types(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Auth types")
     |> stream(:auth_types, list_auth_types(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    auth_type = Providers.get_auth_type!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_auth_type(socket.assigns.current_scope, auth_type)

    {:noreply, stream_delete(socket, :auth_types, auth_type)}
  end

  @impl true
  def handle_info({type, %ServiceHub.Providers.AuthType{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :auth_types, list_auth_types(socket.assigns.current_scope), reset: true)}
  end

  defp list_auth_types(current_scope) do
    Providers.list_auth_types(current_scope)
  end

  defp format_fields(fields) when is_map(fields) and map_size(fields) > 0,
    do: Jason.encode!(fields)

  defp format_fields(_), do: ""
end
