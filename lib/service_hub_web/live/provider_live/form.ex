defmodule ServiceHubWeb.ProviderLive.Form do
  use ServiceHubWeb, :live_view

  alias ServiceHub.AccountConnections
  alias ServiceHub.AccountConnections.AccountConnection
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
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="space-y-4">
            <.input field={@form[:name]} type="text" label="Name" />
            <.input
              field={@form[:provider_type_id]}
              type="select"
              label="Provider type"
              prompt="Select provider type"
              options={Enum.map(@provider_types, &{&1.name, &1.id})}
            />
            <.input
              field={@form[:base_url]}
              type="text"
              label="Base URL"
              placeholder="https://api.github.com"
            />
            <div :if={@provider_key == "github"} class="space-y-1">
              <p class="text-xs text-base-content/70">
                GitHub host helper (API base): github.com o tu instancia Enterprise.
              </p>
              <div class="flex flex-wrap gap-2">
                <.button
                  type="button"
                  phx-click="preset-base-url"
                  phx-value-url="https://api.github.com"
                >
                  Use github.com API
                </.button>
                <.button type="button" phx-click="preset-base-url" phx-value-url="">
                  Clear URL
                </.button>
              </div>
            </div>
          </div>

          <div :if={@provider_key == "github"} class="space-y-4">
            <div class="rounded border border-base-300/80 p-4">
              <p class="text-sm font-semibold mb-2">Connect with GitHub (recommended)</p>
              <p class="text-xs text-base-content/70">
                Conecta por OAuth y rellenamos la credencial para este provider automáticamente.
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <.link
                  class="btn btn-primary inline-flex items-center gap-2"
                  href={~p"/oauth/github/start"}
                  target="_blank"
                >
                  <.icon name="hero-key" class="h-4 w-4" />
                  {if @github_connection, do: "Reconnect GitHub", else: "Connect GitHub"}
                </.link>
                <.button
                  :if={@github_connection}
                  type="button"
                  phx-click="use-account-connection"
                  phx-disable-with="Applying..."
                >
                  Use my GitHub connection
                </.button>
                <.button
                  :if={@use_github_connection}
                  type="button"
                  phx-click="cancel-github-connection"
                >
                  Cancel use
                </.button>
              </div>
              <p :if={@github_connection} class="text-xs text-base-content/60 mt-2">
                Scope: {@github_connection.scope || "not provided"}
              </p>
              <p :if={@use_github_connection} class="text-xs text-success mt-2">
                Using GitHub connection for auth data.
              </p>
            </div>

            <div class="rounded border border-base-300/80 p-4">
              <p class="text-sm font-semibold mb-2">Or select custom auth</p>
              <p class="text-xs text-base-content/70">
                Usa PAT o GitHub App manualmente si prefieres no conectar por OAuth.
              </p>
              <.input
                field={@form[:auth_type_id]}
                type="select"
                label="Auth type"
                prompt="Select auth type"
                options={Enum.map(@auth_types, &{&1.name, &1.id})}
                disabled={disable_auth_select?(@form, @use_github_connection)}
              />
            </div>
          </div>
        </div>

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

        <div :if={@provider_key == "github"} class="space-y-2">
          <h3 class="text-sm font-semibold">GitHub defaults</h3>
          <p class="text-xs text-base-content/70">
            Optional. Use this when the provider represents a single organization to prefill service
            owners and keep health/version endpoints consistent.
          </p>
          <.input
            id="github-organization"
            name="provider[auth_data][organization]"
            label="Organization (optional)"
            type="text"
            value={field_value(@form, "organization")}
          />
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
     |> assign(:provider_key, nil)
     |> assign(:auth_key, nil)
     |> assign(:github_connection, nil)
     |> assign(:use_github_connection, false)
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

  def handle_event("preset-base-url", %{"url" => url}, socket) do
    params =
      (socket.assigns.form.params || %{})
      |> Map.put("base_url", url)

    {:noreply,
     assign_form(
       socket,
       Providers.change_provider(socket.assigns.current_scope, socket.assigns.provider, params)
     )}
  end

  def handle_event("use-account-connection", _params, socket) do
    case socket.assigns.github_connection do
      %AccountConnection{token: token} = connection ->
        params =
          socket.assigns.form.params
          |> ensure_params(socket.assigns.provider)
          |> put_in(["auth_data", "token"], token)
          |> put_scope(connection.scope)
          |> maybe_put_github_oauth_auth_type(socket.assigns.auth_types)

        {:noreply,
         assign_form(
           socket,
           Providers.change_provider(
             socket.assigns.current_scope,
             socket.assigns.provider,
             params
           )
         )
         |> assign(:use_github_connection, true)}

      _ ->
        {:noreply, put_flash(socket, :error, "No GitHub connection available")}
    end
  end

  def handle_event("cancel-github-connection", _params, socket) do
    {:noreply, assign(socket, :use_github_connection, false)}
  end

  def handle_event("save", %{"provider" => provider_params}, socket) do
    provider_params = maybe_apply_oauth_params(provider_params, socket)
    save_provider(socket, socket.assigns.live_action, provider_params)
  end

  defp maybe_apply_oauth_params(provider_params, socket) do
    if socket.assigns.use_github_connection do
      with %AccountConnection{} = conn <- socket.assigns.github_connection do
        provider_params
        |> ensure_params(socket.assigns.provider)
        |> put_in(["auth_data", "token"], conn.token)
        |> put_scope(conn.scope)
        |> maybe_put_github_oauth_auth_type(socket.assigns.auth_types)
      else
        _ -> provider_params
      end
    else
      provider_params
    end
  end

  defp save_provider(socket, :edit, provider_params) do
    case Providers.update_provider(
           socket.assigns.current_scope,
           socket.assigns.provider,
           provider_params
         ) do
      {:ok, provider} ->
        {:ok, provider} =
          Providers.validate_provider_connection(socket.assigns.current_scope, provider)

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
        {:ok, provider} =
          Providers.validate_provider_connection(socket.assigns.current_scope, provider)

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
    provider_type = current_type(form, socket.assigns.provider_types, :provider_type_id)
    auth_type = current_type(form, socket.assigns.auth_types, :auth_type_id)
    provider_field_defs = (provider_type && provider_type.required_fields) || %{}
    auth_field_defs = (auth_type && auth_type.required_fields) || %{}
    github_connection = load_github_connection(socket.assigns.current_scope, provider_type)

    socket
    |> assign(:form, form)
    |> assign(:provider_field_defs, provider_field_defs)
    |> assign(:auth_field_defs, auth_field_defs)
    |> assign(:provider_key, provider_type && provider_type.key)
    |> assign(:auth_key, auth_type && auth_type.key)
    |> assign(:github_connection, github_connection)
    |> assign_new(:use_github_connection, fn -> false end)
  end

  defp current_type(form, types, key_field) do
    type_id = selected_type_id(form, key_field)
    Enum.find(types, &(&1.id == type_id))
  end

  defp selected_type_id(form, key_field) do
    params = form.params || %{}

    type_id =
      params[to_string(key_field)] ||
        params[key_field] ||
        Map.get(form.data, key_field)

    case type_id do
      "" -> nil
      value when is_binary(value) -> String.to_integer(value)
      value -> value
    end
  end

  defp load_github_connection(scope, %{key: "github"}) do
    AccountConnections.get_connection(scope, "github")
  end

  defp load_github_connection(_, _), do: nil

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

  defp put_scope(params, nil), do: params
  defp put_scope(params, scope), do: put_in(params, ["auth_data", "scope"], scope)

  defp ensure_params(nil, provider), do: ensure_params(%{}, provider)

  defp ensure_params(params, provider) when is_map(params) do
    existing_auth_data = (provider && provider.auth_data) || %{}

    params
    |> Map.update("auth_data", existing_auth_data, fn
      map when is_map(map) -> Map.merge(existing_auth_data, map)
      _ -> existing_auth_data
    end)
  end

  defp maybe_put_github_oauth_auth_type(params, auth_types) do
    case github_oauth_id(auth_types) do
      nil -> params
      id -> Map.put(params, "auth_type_id", id)
    end
  end

  defp github_oauth_id(auth_types) do
    auth_types
    |> Enum.find(fn at -> at.key in ["github_oauth", "oauth"] end)
    |> case do
      nil -> nil
      %{id: id} -> id
    end
  end

  defp disable_auth_select?(form, use_github_connection) do
    type =
      form.params
      |> Map.get("provider_type_id")
      |> case do
        "" -> nil
        val -> val
      end

    is_nil(type) or use_github_connection
  end
end
