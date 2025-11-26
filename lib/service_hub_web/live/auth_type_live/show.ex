defmodule ServiceHubWeb.AuthTypeLive.Show do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Auth type {@auth_type.id}
        <:subtitle>This is a auth_type record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/auth_types"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/auth_types/#{@auth_type}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit auth_type
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@auth_type.name}</:item>
        <:item title="Key">{@auth_type.key}</:item>
        <:item title="Required fields">
          {format_fields(@auth_type.required_fields)}
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_auth_types(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Auth type")
     |> assign(:auth_type, Providers.get_auth_type!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %ServiceHub.Providers.AuthType{id: id} = auth_type},
        %{assigns: %{auth_type: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :auth_type, auth_type)}
  end

  def handle_info(
        {:deleted, %ServiceHub.Providers.AuthType{id: id}},
        %{assigns: %{auth_type: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current auth_type was deleted.")
     |> push_navigate(to: ~p"/auth_types")}
  end

  def handle_info({type, %ServiceHub.Providers.AuthType{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp format_fields(fields) when is_map(fields) and map_size(fields) > 0,
    do: Jason.encode!(fields)

  defp format_fields(_), do: ""
end
