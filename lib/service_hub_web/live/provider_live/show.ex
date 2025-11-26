defmodule ServiceHubWeb.ProviderLive.Show do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Provider {@provider.id}
        <:subtitle>This is a provider record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/providers"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/providers/#{@provider}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit provider
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@provider.name}</:item>
        <:item title="Type">{@provider.provider_type && @provider.provider_type.name}</:item>
        <:item title="Base URL">{@provider.base_url}</:item>
        <:item title="Auth type">{@provider.auth_type && @provider.auth_type.name}</:item>
        <:item title="Auth details">{format_auth_data(@provider.auth_data)}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_providers(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Provider")
     |> assign(:provider, Providers.get_provider!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %ServiceHub.Providers.Provider{id: id} = provider},
        %{assigns: %{provider: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :provider, provider)}
  end

  def handle_info(
        {:deleted, %ServiceHub.Providers.Provider{id: id}},
        %{assigns: %{provider: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current provider was deleted.")
     |> push_navigate(to: ~p"/providers")}
  end

  def handle_info({type, %ServiceHub.Providers.Provider{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp format_auth_data(auth_data) when is_map(auth_data) and map_size(auth_data) > 0 do
    auth_data
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.join(", ")
  end

  defp format_auth_data(_), do: ""
end
