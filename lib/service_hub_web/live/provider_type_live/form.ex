defmodule ServiceHubWeb.ProviderTypeLive.Form do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers
  alias ServiceHub.Providers.ProviderType

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage provider_type records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="provider_type-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:key]} type="text" label="Key" />
        <.input
          field={@form[:required_fields]}
          type="textarea"
          label="Required fields (JSON map of field => %{label,type})"
          value={required_fields_value(@form)}
          phx-debounce="500"
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Provider type</.button>
          <.button navigate={return_path(@current_scope, @return_to, @provider_type)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    provider_type = Providers.get_provider_type!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Provider type")
    |> assign(:provider_type, provider_type)
    |> assign(
      :form,
      to_form(Providers.change_provider_type(socket.assigns.current_scope, provider_type))
    )
  end

  defp apply_action(socket, :new, _params) do
    provider_type = %ProviderType{}

    socket
    |> assign(:page_title, "New Provider type")
    |> assign(:provider_type, provider_type)
    |> assign(
      :form,
      to_form(Providers.change_provider_type(socket.assigns.current_scope, provider_type))
    )
  end

  @impl true
  def handle_event("validate", %{"provider_type" => provider_type_params}, socket) do
    changeset =
      Providers.change_provider_type(
        socket.assigns.current_scope,
        socket.assigns.provider_type,
        provider_type_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"provider_type" => provider_type_params}, socket) do
    save_provider_type(socket, socket.assigns.live_action, provider_type_params)
  end

  defp save_provider_type(socket, :edit, provider_type_params) do
    case Providers.update_provider_type(
           socket.assigns.current_scope,
           socket.assigns.provider_type,
           provider_type_params
         ) do
      {:ok, provider_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider type updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, provider_type)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_provider_type(socket, :new, provider_type_params) do
    case Providers.create_provider_type(socket.assigns.current_scope, provider_type_params) do
      {:ok, provider_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider type created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, provider_type)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _provider_type), do: ~p"/provider_types"
  defp return_path(_scope, "show", provider_type), do: ~p"/provider_types/#{provider_type}"

  defp required_fields_value(%{source: %{params: %{"required_fields" => value}}})
       when is_binary(value),
       do: value

  defp required_fields_value(%{source: %{data: %{required_fields: fields}}}) when is_map(fields),
    do: Jason.encode!(fields)

  defp required_fields_value(_), do: ""
end
