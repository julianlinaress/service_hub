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
              disabled={@live_action == :edit}
            />
            <.input
              field={@form[:base_url]}
              type="text"
              label="Base URL"
              placeholder="https://api.github.com"
              disabled={@live_action == :edit}
            />
            <div :if={String.downcase(@provider_key || "") == "github"} class="space-y-1">
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

            <div :if={String.downcase(@provider_key || "") == "gitea"} class="space-y-1">
              <p class="text-xs text-base-content/70">
                Gitea instance URL (e.g., https://gitea.example.com)
              </p>
            </div>
          </div>

          <div :if={String.downcase(@provider_key || "") == "github"} class="space-y-4">
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

          <div :if={String.downcase(@provider_key || "") == "gitea"} class="space-y-4">
            <div class="rounded border border-base-300/80 p-4">
              <p class="text-sm font-semibold mb-2">Generate Token (Optional)</p>
              <p class="text-xs text-base-content/70 mb-3">
                Generate a Gitea access token using your Gitea username (not email) and password
              </p>

              <div class="space-y-3">
                <div>
                  <label class="block text-sm font-medium mb-1">Gitea Username</label>
                  <input
                    type="text"
                    class="input input-bordered w-full"
                    placeholder="Enter your Gitea username"
                    value={@gitea_username}
                    phx-blur="update-gitea-username"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">Gitea Password</label>
                  <input
                    type="password"
                    class="input input-bordered w-full"
                    placeholder="Enter your Gitea password"
                    value={@gitea_password}
                    phx-blur="update-gitea-password"
                  />
                </div>
                <.button
                  type="button"
                  phx-click="generate-gitea-token"
                  phx-disable-with="Generating..."
                >
                  <.icon name="hero-key" class="h-4 w-4" /> Generate Token
                </.button>
                <p :if={@gitea_token_generated} class="text-xs text-success">
                  Token generated and applied to auth data
                </p>
                <p :if={@gitea_token_error} class="text-xs text-error">
                  {@gitea_token_error}
                </p>
              </div>
            </div>

            <div class="rounded border border-base-300/80 p-4">
              <p class="text-sm font-semibold mb-2">Or select auth type manually</p>
              <p class="text-xs text-base-content/70 mb-3">
                If you already have a token, select the auth type
              </p>
              <.input
                field={@form[:auth_type_id]}
                type="select"
                label="Auth type"
                prompt="Select auth type"
                options={Enum.map(filter_auth_types(@auth_types, @provider_key), &{&1.name, &1.id})}
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

        <div :if={String.downcase(@provider_key || "") == "github"} class="space-y-2">
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

      <%!-- Danger Zone --%>
      <div :if={@live_action == :edit} class="mt-8 border border-error/30 rounded-lg p-6">
        <h2 class="text-lg font-semibold text-error mb-2">Danger Zone</h2>
        <p class="text-sm text-base-content/70 mb-4">
          These actions can break existing services and connections. Proceed with caution.
        </p>

        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 border border-base-300 rounded">
            <div>
              <div class="font-medium text-sm">Change Provider Type</div>
              <div class="text-xs text-base-content/60">
                Changing the provider type may break existing services
              </div>
            </div>
            <.button
              phx-click="confirm-change-type"
              variant="ghost"
              size="sm"
              class="text-error hover:bg-error/10"
            >
              Change Type
            </.button>
          </div>

          <div class="flex items-center justify-between p-3 border border-base-300 rounded">
            <div>
              <div class="font-medium text-sm">Change Base URL</div>
              <div class="text-xs text-base-content/60">
                Changing the URL will affect all API calls to this provider
              </div>
            </div>
            <.button
              phx-click="confirm-change-url"
              variant="ghost"
              size="sm"
              class="text-error hover:bg-error/10"
            >
              Change URL
            </.button>
          </div>

          <div class="flex items-center justify-between p-3 border border-base-300 rounded">
            <div>
              <div class="font-medium text-sm">Delete Provider</div>
              <div class="text-xs text-base-content/60">
                This will permanently delete all services and connections
              </div>
            </div>
            <.button
              phx-click="confirm-delete"
              variant="ghost"
              size="sm"
              class="text-error hover:bg-error/10"
            >
              Delete Provider
            </.button>
          </div>
        </div>
      </div>

      <%!-- Confirmation Modal --%>
      <dialog :if={@show_danger_modal} id="danger-modal" class="modal modal-open">
        <div class="modal-box max-w-lg">
          <.form for={@danger_form} id="danger-form" phx-submit="execute-danger">
            <div class="space-y-4">
              <div class="flex items-center gap-3">
                <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-error" />
                <h3 class="text-lg font-semibold">{@danger_modal_title}</h3>
              </div>

              <p class="text-sm text-base-content/70">{@danger_modal_message}</p>

              <%!-- Provider Type Selector --%>
              <div :if={@danger_action == :change_type}>
                <.input
                  field={@danger_form[:provider_type_id]}
                  type="select"
                  label="New Provider Type"
                  prompt="Select new provider type"
                  options={Enum.map(@provider_types, &{&1.name, &1.id})}
                  required
                />
                <p class="text-xs text-warning mt-2">
                  Warning: Changing the provider type may break existing services.
                </p>
              </div>

              <%!-- Base URL Input --%>
              <div :if={@danger_action == :change_url}>
                <.input
                  field={@danger_form[:base_url]}
                  type="text"
                  label="New Base URL"
                  placeholder="https://api.github.com"
                  required
                />
                <p class="text-xs text-warning mt-2">
                  Warning: All API calls will use this new URL.
                </p>
              </div>

              <%!-- Delete Warning --%>
              <div
                :if={@danger_action == :delete}
                class="bg-error/10 border border-error/30 rounded p-3"
              >
                <p class="text-sm text-error font-medium">
                  This action cannot be undone. All services, connections, and data will be permanently lost.
                </p>
              </div>

              <div class="flex justify-end gap-3 mt-6">
                <.button type="button" phx-click="cancel-danger" variant="ghost">Cancel</.button>
                <.button
                  type="submit"
                  variant="primary"
                  class="bg-error hover:bg-error/90"
                  phx-disable-with="Processing..."
                >
                  {danger_confirm_text(@danger_action)}
                </.button>
              </div>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="cancel-danger">
          <button>close</button>
        </form>
      </dialog>
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
     |> assign(:show_danger_modal, false)
     |> assign(:danger_action, nil)
     |> assign(:danger_modal_title, "")
     |> assign(:danger_modal_message, "")
     |> assign(:danger_form, to_form(%{}))
     |> assign(:gitea_token_generated, false)
     |> assign(:gitea_token_error, nil)
     |> assign(:gitea_username, "")
     |> assign(:gitea_password, "")
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

  def handle_event("update-gitea-username", %{"value" => value}, socket) do
    {:noreply, assign(socket, :gitea_username, value)}
  end

  def handle_event("update-gitea-password", %{"value" => value}, socket) do
    {:noreply, assign(socket, :gitea_password, value)}
  end

  def handle_event("generate-gitea-token", _params, socket) do
    username = socket.assigns.gitea_username
    password = socket.assigns.gitea_password

    cond do
      String.trim(username) == "" or String.trim(password) == "" ->
        {:noreply,
         socket
         |> assign(:gitea_token_generated, false)
         |> assign(:gitea_token_error, "Username and password are required")}

      socket.assigns.provider.id == nil ->
        {:noreply,
         socket
         |> assign(:gitea_token_generated, false)
         |> assign(:gitea_token_error, "Please save the provider first before generating a token")}

      true ->
        case ServiceHub.ProviderAdapters.Gitea.create_token(
               socket.assigns.provider,
               username,
               password,
               %{name: "ServiceHub - #{socket.assigns.provider.name}"}
             ) do
          {:ok, token} when is_binary(token) ->
            params =
              socket.assigns.form.params
              |> ensure_params(socket.assigns.provider)
              |> put_in(["auth_data", "token"], token)
              |> maybe_put_token_auth_type(socket.assigns.auth_types)

            {:noreply,
             socket
             |> assign(:gitea_token_generated, true)
             |> assign(:gitea_token_error, nil)
             |> assign_form(
               Providers.change_provider(
                 socket.assigns.current_scope,
                 socket.assigns.provider,
                 params
               )
             )}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> assign(:gitea_token_generated, false)
             |> assign(:gitea_token_error, "Invalid username or password")}

          {:error, {:unexpected_status, 404, %{"message" => message}}} ->
            {:noreply,
             socket
             |> assign(:gitea_token_generated, false)
             |> assign(
               :gitea_token_error,
               "User not found. Use your Gitea username, not email. (#{message})"
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:gitea_token_generated, false)
             |> assign(:gitea_token_error, "Failed to generate token: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("save", %{"provider" => provider_params}, socket) do
    provider_params = maybe_apply_oauth_params(provider_params, socket)
    save_provider(socket, socket.assigns.live_action, provider_params)
  end

  # Danger Zone handlers
  def handle_event("confirm-change-type", _, socket) do
    {:noreply,
     socket
     |> assign(:show_danger_modal, true)
     |> assign(:danger_action, :change_type)
     |> assign(:danger_modal_title, "Change Provider Type?")
     |> assign(
       :danger_modal_message,
       "Select the new provider type. This may break existing services that depend on this provider."
     )
     |> assign(
       :danger_form,
       to_form(%{"provider_type_id" => socket.assigns.provider.provider_type_id})
     )}
  end

  def handle_event("confirm-change-url", _, socket) do
    {:noreply,
     socket
     |> assign(:show_danger_modal, true)
     |> assign(:danger_action, :change_url)
     |> assign(:danger_modal_title, "Change Base URL?")
     |> assign(
       :danger_modal_message,
       "Enter the new base URL. All API calls will use this URL."
     )
     |> assign(:danger_form, to_form(%{"base_url" => socket.assigns.provider.base_url}))}
  end

  def handle_event("confirm-delete", _, socket) do
    {:noreply,
     socket
     |> assign(:show_danger_modal, true)
     |> assign(:danger_action, :delete)
     |> assign(:danger_modal_title, "Delete Provider?")
     |> assign(
       :danger_modal_message,
       "Are you sure you want to delete \"#{socket.assigns.provider.name}\"? This will permanently delete all associated services, service clients, and configurations."
     )}
  end

  def handle_event("cancel-danger", _, socket) do
    {:noreply,
     socket
     |> assign(:show_danger_modal, false)
     |> assign(:danger_action, nil)}
  end

  def handle_event("execute-danger", %{"provider_type_id" => provider_type_id}, socket)
      when socket.assigns.danger_action == :change_type do
    case Providers.update_provider(
           socket.assigns.current_scope,
           socket.assigns.provider,
           %{"provider_type_id" => provider_type_id}
         ) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> assign(:provider, provider)
         |> assign(:show_danger_modal, false)
         |> assign_form(Providers.change_provider(socket.assigns.current_scope, provider))
         |> put_flash(:info, "Provider type updated successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:danger_form, to_form(changeset))
         |> put_flash(:error, "Failed to update provider type")}
    end
  end

  def handle_event("execute-danger", %{"base_url" => base_url}, socket)
      when socket.assigns.danger_action == :change_url do
    case Providers.update_provider(
           socket.assigns.current_scope,
           socket.assigns.provider,
           %{"base_url" => base_url}
         ) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> assign(:provider, provider)
         |> assign(:show_danger_modal, false)
         |> assign_form(Providers.change_provider(socket.assigns.current_scope, provider))
         |> put_flash(:info, "Base URL updated successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:danger_form, to_form(changeset))
         |> put_flash(:error, "Failed to update base URL")}
    end
  end

  def handle_event("execute-danger", _params, socket)
      when socket.assigns.danger_action == :delete do
    case Providers.delete_provider(socket.assigns.current_scope, socket.assigns.provider) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider deleted successfully")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete provider")
         |> assign(:show_danger_modal, false)}
    end
  end

  def handle_event("execute-danger", _params, socket) do
    {:noreply, assign(socket, :show_danger_modal, false)}
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
        # Try to validate, but don't fail if validation fails (e.g., missing token)
        _result = Providers.validate_provider_connection(socket.assigns.current_scope, provider)

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

  defp return_path(_scope, "index", _provider), do: ~p"/config/providers"
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

  defp maybe_put_token_auth_type(params, auth_types) do
    case token_auth_type_id(auth_types) do
      nil -> params
      id -> Map.put(params, "auth_type_id", id)
    end
  end

  defp token_auth_type_id(auth_types) do
    auth_types
    |> Enum.find(fn at -> at.key == "token" end)
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

  defp danger_confirm_text(:delete), do: "Yes, Delete Provider"
  defp danger_confirm_text(:change_type), do: "Yes, I Understand"
  defp danger_confirm_text(:change_url), do: "Yes, I Understand"
  defp danger_confirm_text(_), do: "Confirm"

  defp filter_auth_types(_auth_types, nil), do: []

  defp filter_auth_types(auth_types, provider_key) do
    provider_key_lower = String.downcase(provider_key)

    Enum.filter(auth_types, fn auth_type ->
      # Only show if the provider is explicitly in the compatible list
      Enum.any?(auth_type.compatible_providers, fn p ->
        String.downcase(p) == provider_key_lower
      end)
    end)
  end
end
