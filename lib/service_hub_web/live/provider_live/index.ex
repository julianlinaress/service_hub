defmodule ServiceHubWeb.ProviderLive.Index do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Providers
        <:actions>
          <.button variant="primary" navigate={~p"/providers/new"}>
            <.icon name="hero-plus" /> New Provider
          </.button>
        </:actions>
      </.header>

      <.table
        id="providers"
        rows={@streams.providers}
        row_click={fn {_id, provider} -> JS.navigate(~p"/providers/#{provider}") end}
      >
        <:col :let={{_id, provider}} label="Name">{provider.name}</:col>
        <:col :let={{_id, provider}} label="Type">
          {provider.provider_type && provider.provider_type.name}
        </:col>
        <:col :let={{_id, provider}} label="Base URL">{provider.base_url}</:col>
        <:col :let={{_id, provider}} label="Auth type">
          {provider.auth_type && provider.auth_type.name}
        </:col>
        <:col :let={{_id, provider}} label="Auth details">
          {format_auth_data(provider.auth_data)}
        </:col>
        <:action :let={{_id, provider}}>
          <div class="sr-only">
            <.link navigate={~p"/providers/#{provider}"}>Show</.link>
          </div>
          <.link navigate={~p"/providers/#{provider}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, provider}}>
          <.link
            phx-click={JS.push("delete", value: %{id: provider.id}) |> hide("##{id}")}
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
      Providers.subscribe_providers(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Providers")
     |> stream(:providers, list_providers(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_provider(socket.assigns.current_scope, provider)

    {:noreply, stream_delete(socket, :providers, provider)}
  end

  @impl true
  def handle_info({type, %ServiceHub.Providers.Provider{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :providers, list_providers(socket.assigns.current_scope), reset: true)}
  end

  defp list_providers(current_scope) do
    Providers.list_providers(current_scope)
  end

  defp format_auth_data(auth_data) when is_map(auth_data) and map_size(auth_data) > 0 do
    auth_data
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.join(", ")
  end

  defp format_auth_data(_), do: ""
end
