defmodule ServiceHubWeb.ProviderTypeLive.Show do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Provider type {@provider_type.id}
        <:subtitle>This is a provider_type record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/provider_types"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/provider_types/#{@provider_type}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit provider_type
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@provider_type.name}</:item>
        <:item title="Key">{@provider_type.key}</:item>
        <:item title="Required fields">
          {format_fields(@provider_type.required_fields)}
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_provider_types(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Provider type")
     |> assign(:provider_type, Providers.get_provider_type!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %ServiceHub.Providers.ProviderType{id: id} = provider_type},
        %{assigns: %{provider_type: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :provider_type, provider_type)}
  end

  def handle_info(
        {:deleted, %ServiceHub.Providers.ProviderType{id: id}},
        %{assigns: %{provider_type: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current provider_type was deleted.")
     |> push_navigate(to: ~p"/provider_types")}
  end

  def handle_info({type, %ServiceHub.Providers.ProviderType{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp format_fields(fields) when is_map(fields) and map_size(fields) > 0,
    do: Jason.encode!(fields)

  defp format_fields(_), do: ""
end
