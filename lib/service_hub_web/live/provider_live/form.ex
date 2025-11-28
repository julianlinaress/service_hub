defmodule ServiceHubWeb.ProviderLive.Form do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers
  alias ServiceHub.Providers.Provider

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage provider records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="provider-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input
          field={@form[:provider_type_id]}
          type="select"
          label="Provider type"
          prompt="Select provider type"
          options={Enum.map(@provider_types, &{&1.name, &1.id})}
        />
        <.input field={@form[:base_url]} type="text" label="Base URL" />
        <.input
          field={@form[:auth_type_id]}
          type="select"
          label="Auth type"
          prompt="Select auth type"
          options={Enum.map(@auth_types, &{&1.name, &1.id})}
        />

        <div :if={map_size(@provider_field_defs) > 0} class="space-y-2">
          <h3 class="text-sm font-semibold">Provider settings</h3>
          <div :for={{key, spec} <- @provider_field_defs} class="space-y-1">
            <.input
              id={"provider-field-#{key}"}
              name={"provider[auth_data][#{key}]"}
              label={field_label(key, spec)}
              type={field_input_type(spec)}
              value={field_value(@form, key)}
            />
          </div>
        </div>

        <div :if={map_size(@auth_field_defs) > 0} class="space-y-2">
          <h3 class="text-sm font-semibold">Auth settings</h3>
          <div :for={{key, spec} <- @auth_field_defs} class="space-y-1">
            <.input
              id={"auth-field-#{key}"}
              name={"provider[auth_data][#{key}]"}
              label={field_label(key, spec)}
              type={field_input_type(spec)}
              value={field_value(@form, key)}
            />
          </div>
        </div>

        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Provider</.button>
          <.button navigate={return_path(@current_scope, @return_to, @provider)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:provider_types, Providers.list_provider_types(socket.assigns.current_scope))
     |> assign(:auth_types, Providers.list_auth_types(socket.assigns.current_scope))
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:provider_field_defs, %{})
     |> assign(:auth_field_defs, %{})
     |> apply_action(socket.assigns.live_action, params)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Provider")
    |> assign(:provider, provider)
    |> assign_form(Providers.change_provider(socket.assigns.current_scope, provider))
  end

  defp apply_action(socket, :new, _params) do
    provider = %Provider{}

    socket
    |> assign(:page_title, "New Provider")
    |> assign(:provider, provider)
    |> assign_form(Providers.change_provider(socket.assigns.current_scope, provider))
  end

  @impl true
  def handle_event("validate", %{"provider" => provider_params}, socket) do
    changeset =
      Providers.change_provider(
        socket.assigns.current_scope,
        socket.assigns.provider,
        provider_params
      )

    {:noreply, assign_form(socket, %{changeset | action: :validate})}
  end

  def handle_event("save", %{"provider" => provider_params}, socket) do
    save_provider(socket, socket.assigns.live_action, provider_params)
  end

  defp save_provider(socket, :edit, provider_params) do
    case Providers.update_provider(
           socket.assigns.current_scope,
           socket.assigns.provider,
           provider_params
         ) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, provider)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_provider(socket, :new, provider_params) do
    case Providers.create_provider(socket.assigns.current_scope, provider_params) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, provider)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp return_path(_scope, "index", _provider), do: ~p"/providers"
  defp return_path(_scope, "show", provider), do: ~p"/providers/#{provider}"

  defp assign_form(socket, changeset) do
    form = to_form(changeset)
    provider_field_defs = type_fields(form, socket.assigns.provider_types, :provider_type_id)
    auth_field_defs = type_fields(form, socket.assigns.auth_types, :auth_type_id)

    socket
    |> assign(:form, form)
    |> assign(:provider_field_defs, provider_field_defs)
    |> assign(:auth_field_defs, auth_field_defs)
  end

  defp type_fields(form, types, key_field) do
    params = form.params || %{}

    type_id =
      params[to_string(key_field)] ||
        params[key_field] ||
        Map.get(form.data, key_field)

    type_id =
      case type_id do
        "" -> nil
        value when is_binary(value) -> String.to_integer(value)
        value -> value
      end

    case Enum.find(types, &(&1.id == type_id)) do
      nil -> %{}
      type -> type.required_fields || %{}
    end
  end

  defp field_label(_key, %{"label" => label}) when is_binary(label), do: label
  defp field_label(key, _), do: Phoenix.Naming.humanize(key)

  defp field_input_type(%{"type" => type}) when is_binary(type), do: type
  defp field_input_type(type) when is_binary(type), do: type
  defp field_input_type(_), do: "text"

  defp field_value(form, key) do
    auth_data =
      case form do
        %{params: %{"auth_data" => data}} when is_map(data) -> data
        %{params: %{auth_data: data}} when is_map(data) -> data
        %{data: %{auth_data: data}} when is_map(data) -> data
        _ -> %{}
      end

    Map.get(auth_data, key) || Map.get(auth_data, to_string(key)) || ""
  end
end
