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
    |> assign(:form, to_form(Providers.change_auth_type(socket.assigns.current_scope, auth_type)))
  end

  defp apply_action(socket, :new, _params) do
    auth_type = %AuthType{}

    socket
    |> assign(:page_title, "New Auth type")
    |> assign(:auth_type, auth_type)
    |> assign(:form, to_form(Providers.change_auth_type(socket.assigns.current_scope, auth_type)))
  end

  @impl true
  def handle_event("validate", %{"auth_type" => auth_type_params}, socket) do
    changeset =
      Providers.change_auth_type(
        socket.assigns.current_scope,
        socket.assigns.auth_type,
        auth_type_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"auth_type" => auth_type_params}, socket) do
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

  defp return_path(_scope, "index", _auth_type), do: ~p"/auth_types"
  defp return_path(_scope, "show", auth_type), do: ~p"/auth_types/#{auth_type}"

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
end
