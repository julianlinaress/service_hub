defmodule ServiceHubWeb.AuthTypeLive.Form do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers
  alias ServiceHub.Providers.AuthType
  alias ServiceHub.Providers.AuthRegistry

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage auth_type records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="auth_type-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:key]} type="select" label="Auth type" options={@auth_type_options} />

        <div>
          <div class="flex items-center justify-between mb-2">
            <label class="block text-sm font-medium text-base-content">
              Compatible Providers
            </label>
            <button
              type="button"
              phx-click="select-all-providers"
              class="text-xs text-primary hover:underline"
            >
              Select All
            </button>
          </div>
          <p class="text-xs text-base-content/60 mb-2">
            Select which provider types can use this auth type.
          </p>
          <div class="space-y-2">
            <label
              :for={provider_type <- @provider_types}
              class="flex items-center gap-2 p-2 rounded hover:bg-base-200/50 cursor-pointer"
            >
              <input
                type="checkbox"
                phx-click="toggle-provider"
                phx-value-key={provider_type.key}
                checked={provider_type.key in @selected_providers}
                class="checkbox checkbox-sm"
              />
              <span class="text-sm">
                {provider_type.name}
                <code class="text-xs text-base-content/60">({provider_type.key})</code>
              </span>
            </label>
          </div>
          <input
            type="hidden"
            name="auth_type[compatible_providers]"
            value={Jason.encode!(@selected_providers)}
          />
        </div>

        <div class="rounded border border-base-200 bg-base-200/30 p-3 text-sm">
          <p class="font-semibold mb-2">Required fields</p>
          <pre class="whitespace-pre-wrap text-xs">
    {required_fields_value(@form)}
          </pre>
        </div>
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Auth type</.button>
          <.button navigate={return_path(@current_scope, @return_to, @auth_type)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:auth_type_options, AuthRegistry.list_options())
     |> assign(:provider_types, Providers.list_provider_types(socket.assigns.current_scope))
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    auth_type = Providers.get_auth_type!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Auth type")
    |> assign(:auth_type, auth_type)
    |> assign(:selected_providers, auth_type.compatible_providers || [])
    |> assign(:form, to_form(Providers.change_auth_type(socket.assigns.current_scope, auth_type)))
  end

  defp apply_action(socket, :new, _params) do
    auth_type = %AuthType{}

    socket
    |> assign(:page_title, "New Auth type")
    |> assign(:auth_type, auth_type)
    |> assign(:selected_providers, [])
    |> assign(:form, to_form(Providers.change_auth_type(socket.assigns.current_scope, auth_type)))
  end

  @impl true
  def handle_event("toggle-provider", %{"key" => key}, socket) do
    selected_providers =
      if key in socket.assigns.selected_providers do
        List.delete(socket.assigns.selected_providers, key)
      else
        [key | socket.assigns.selected_providers]
      end

    {:noreply, assign(socket, :selected_providers, selected_providers)}
  end

  def handle_event("select-all-providers", _, socket) do
    all_keys = Enum.map(socket.assigns.provider_types, & &1.key)
    {:noreply, assign(socket, :selected_providers, all_keys)}
  end

  def handle_event("validate", %{"auth_type" => auth_type_params}, socket) do
    auth_type_params = decode_compatible_providers(auth_type_params)

    changeset =
      Providers.change_auth_type(
        socket.assigns.current_scope,
        socket.assigns.auth_type,
        auth_type_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"auth_type" => auth_type_params}, socket) do
    auth_type_params = decode_compatible_providers(auth_type_params)
    save_auth_type(socket, socket.assigns.live_action, auth_type_params)
  end

  defp save_auth_type(socket, :edit, auth_type_params) do
    case Providers.update_auth_type(
           socket.assigns.current_scope,
           socket.assigns.auth_type,
           auth_type_params
         ) do
      {:ok, auth_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Auth type updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, auth_type)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_auth_type(socket, :new, auth_type_params) do
    case Providers.create_auth_type(socket.assigns.current_scope, auth_type_params) do
      {:ok, auth_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Auth type created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, auth_type)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _auth_type), do: ~p"/config/auth-types"
  defp return_path(_scope, "show", auth_type), do: ~p"/config/auth-types/#{auth_type}"

  defp required_fields_value(form) do
    key =
      case form do
        %{source: %{params: %{"key" => key}}} when is_binary(key) -> key
        %{source: %{data: %{key: key}}} when is_binary(key) -> key
        _ -> nil
      end

    case AuthRegistry.fetch(key) do
      {:ok, %{required_fields: fields}} -> Jason.encode!(fields)
      _ -> ""
    end
  end

  defp decode_compatible_providers(params) do
    case params do
      %{"compatible_providers" => json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) ->
            Map.put(params, "compatible_providers", list)

          _ ->
            Map.put(params, "compatible_providers", [])
        end

      _ ->
        params
    end
  end
end
