defmodule ServiceHubWeb.ProviderLive.Show do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers
  alias ServiceHub.Services
  alias ServiceHub.Services.Service

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Provider {@provider.name}
        <:subtitle>Manage the provider and its services.</:subtitle>
        <:actions>
          <.button navigate={~p"/config/providers"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/providers/#{@provider}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit provider
          </.button>
          <.button phx-click="validate-connection" variant="primary">
            <.icon name="hero-check-badge" /> Validate connection
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@provider.name}</:item>
        <:item title="Type">{@provider.provider_type && @provider.provider_type.name}</:item>
        <:item title="Base URL">{@provider.base_url}</:item>
        <:item title="Auth type">{@provider.auth_type && @provider.auth_type.name}</:item>
        <:item title="Validation status">
          <span class="badge badge-outline">
            {String.capitalize(@provider.last_validation_status || "unvalidated")}
          </span>
          <span :if={@provider.last_validated_at} class="ml-2 text-sm text-base-content/70">
            Last checked: {format_ts(@provider.last_validated_at)}
          </span>
          <p :if={@provider.last_validation_error} class="text-sm text-warning">
            {@provider.last_validation_error}
          </p>
        </:item>
      </.list>

      <section class="mt-8 space-y-4">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="text-xl font-semibold">Services</h2>
            <p class="text-sm text-base-content/70">Linked repositories for this provider.</p>
          </div>
          <div class="flex items-center gap-3">
            <.button
              :if={provider_validated?(@provider)}
              variant="primary"
              patch={~p"/providers/#{@provider}/services/new"}
            >
              <.icon name="hero-plus" /> New service
            </.button>
            <.button :if={!provider_validated?(@provider)} variant="primary" disabled>
              <.icon name="hero-plus" /> New service
            </.button>
            <span :if={!provider_validated?(@provider)} class="text-sm text-base-content/70">
              Validate this provider before adding or editing services.
            </span>
          </div>
        </div>

        <.table id="services" rows={@services}>
          <:col :let={service} label="Name">{service.name}</:col>
        <:col :let={service} label="Owner/Repo">
          {service.owner}/{service.repo}
        </:col>
        <:col :let={service} label="Default ref">{service.default_ref}</:col>
        <:col :let={service} label="Version endpoint">
          {service.version_endpoint_template || "https://{{host}}/api/version"}
        </:col>
        <:col :let={service} label="Health endpoint">
          {service.healthcheck_endpoint_template || "https://{{host}}/api/health"}
        </:col>
          <:action :let={service}>
            <div :if={provider_validated?(@provider)} class="sr-only">
              <.link patch={~p"/providers/#{@provider}/services/#{service.id}/edit"}>Edit</.link>
            </div>
            <.link
              :if={provider_validated?(@provider)}
              patch={~p"/providers/#{@provider}/services/#{service.id}/edit"}
            >
              Edit
            </.link>
            <span
              :if={!provider_validated?(@provider)}
              class="text-xs text-base-content/60"
            >
              Validate provider to edit
            </span>
          </:action>
          <:action :let={service}>
            <.link
              phx-click="delete-service"
              phx-value-id={service.id}
              data-confirm="Delete this service?"
            >
              Delete
            </.link>
          </:action>
        </.table>
      </section>

      <section
        :if={@live_action in [:new_service, :edit_service] and provider_validated?(@provider)}
        class="mt-8"
      >
        <.live_component
          module={ServiceHubWeb.ServiceLive.FormComponent}
          id="service-form"
          title={@page_title}
          action={@live_action}
          provider={@provider}
          service={@service}
          return_to={~p"/providers/#{@provider}"}
          current_scope={@current_scope}
        />
      </section>

      <section :if={provider_key(@provider) == "github"} class="mt-8">
        <div class="card bg-base-100 shadow-md">
          <div class="card-body space-y-4">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="text-xl font-semibold">GitHub setup</h2>
                <p class="text-sm text-base-content/70">
                  Works with personal accounts or organizations. Configuration stays in the database.
                </p>
              </div>
              <div class="flex items-center gap-2">
                <span class="badge badge-outline">
                  Auth: {(@provider.auth_type && @provider.auth_type.name) || "Not set"}
                </span>
                <.button
                  :if={oauth_capable?(@provider)}
                  navigate={~p"/oauth/github/start"}
                  variant="primary"
                >
                  <.icon name="hero-key" class="h-4 w-4" />
                  {oauth_button_label(@provider)}
                </.button>
              </div>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <div class="space-y-2 rounded border border-base-300/80 p-4">
                <p class="flex items-center gap-2 text-sm font-semibold">
                  <.icon name="hero-building-office-2" class="h-4 w-4" /> Ownership & host
                </p>
                <p class="text-sm text-base-content/70">Base URL: {@provider.base_url}</p>
                <p class="text-sm text-base-content/70">
                  Default org: {default_owner(@provider) || "Not set"}
                </p>
                <p class="text-xs text-base-content/60">
                  Services default to this owner; you can override per repo when adding services.
                </p>
              </div>

              <div class="space-y-2 rounded border border-base-300/80 p-4">
                <p class="flex items-center gap-2 text-sm font-semibold">
                  <.icon name="hero-lock-closed" class="h-4 w-4" /> Auth options
                </p>
                <ul class="list-disc space-y-1 pl-4 text-sm text-base-content/70">
                  <li>
                    Personal access token: store it in auth data (fine-grained or classic). Ideal for
                    quick setups.
                  </li>
                  <li>
                    GitHub App installation: set App ID, installation ID, and PEM key to mint
                    installation tokens automatically.
                  </li>
                  <li>
                    OAuth app: connect once and store tokens securely in this provider.
                  </li>
                </ul>
                <a
                  href="https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api?apiVersion=2022-11-28"
                  class="link text-sm"
                  target="_blank"
                >
                  View GitHub REST auth guide
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section :if={provider_key(@provider) == "gitea"} class="mt-8 space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-xl font-semibold">Gitea token helper</h2>
            <p class="text-sm text-base-content/70">
              Create a personal access token using your Gitea username/password.
            </p>
          </div>
          <.button phx-click="toggle-token-form">
            <.icon name={(@show_token_form && "hero-x-mark") || "hero-key"} />
            {(@show_token_form && "Close") || "Generate token"}
          </.button>
        </div>

        <div :if={@show_token_form} class="card bg-base-100 shadow-md">
          <div class="card-body space-y-4">
            <.form for={@token_form} id="token-form" phx-submit="generate-token">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <.input field={@token_form[:username]} type="text" label="Username" required />
                <.input field={@token_form[:password]} type="password" label="Password" required />
                <.input
                  field={@token_form[:name]}
                  type="text"
                  label="Token name"
                  value={@token_form[:name].value || "service_hub_token"}
                />
              </div>
              <p class="text-xs text-base-content/70">
                Token will be saved into this provider's auth data for future API calls.
              </p>
              <footer class="mt-2 flex gap-3">
                <.button variant="primary" phx-disable-with="Creating...">Create token</.button>
                <.button type="button" phx-click="toggle-token-form">Cancel</.button>
              </footer>
            </.form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Providers.subscribe_providers(socket.assigns.current_scope)
      Services.subscribe_services(socket.assigns.current_scope, provider.id)
    end

    {:ok,
     socket
     |> assign(:provider, provider)
     |> assign(
       :services,
       Services.list_services_for_provider(socket.assigns.current_scope, provider)
     )
     |> assign(:token_form, token_form())
     |> assign(:show_token_form, false)
     |> assign(:service, nil)
     |> assign(:page_title, page_title(socket.assigns.live_action))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info(
        {:updated, %ServiceHub.Providers.Provider{id: id} = provider},
        %{assigns: %{provider: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:provider, provider)
     |> assign(
       :services,
       Services.list_services_for_provider(socket.assigns.current_scope, provider)
     )}
  end

  def handle_info(
        {:deleted, %ServiceHub.Providers.Provider{id: id}},
        %{assigns: %{provider: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current provider was deleted.")
     |> push_navigate(to: ~p"/config/providers")}
  end

  def handle_info({type, %ServiceHub.Providers.Provider{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  def handle_info({type, %Service{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply,
     assign(
       socket,
       :services,
       Services.list_services_for_provider(socket.assigns.current_scope, socket.assigns.provider)
     )}
  end

  def handle_info({ServiceHubWeb.ServiceLive.FormComponent, {:saved, _service}}, socket) do
    {:noreply,
     assign(
       socket,
       :services,
       Services.list_services_for_provider(socket.assigns.current_scope, socket.assigns.provider)
     )}
  end

  @impl true
  def handle_event("delete-service", %{"id" => id}, socket) do
    service = Services.get_service!(socket.assigns.current_scope, id)
    {:ok, _} = Services.delete_service(socket.assigns.current_scope, service)

    {:noreply,
     assign(
       socket,
       :services,
       Services.list_services_for_provider(socket.assigns.current_scope, socket.assigns.provider)
     )}
  end

  def handle_event("validate-connection", _params, socket) do
    case Providers.validate_provider_connection(
           socket.assigns.current_scope,
           socket.assigns.provider
         ) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> assign(:provider, provider)
         |> put_flash(:info, "Validation completed")}

      {:error, _} = error ->
        {:noreply, put_flash(socket, :error, "Validation failed: #{inspect(error)}")}
    end
  end

  def handle_event("toggle-token-form", _params, socket) do
    {:noreply,
     socket
     |> update(:show_token_form, fn v -> !v end)
     |> assign(:token_form, token_form())}
  end

  def handle_event("generate-token", %{"token" => params}, socket) do
    case Providers.create_provider_token(
           socket.assigns.current_scope,
           socket.assigns.provider,
           params
         ) do
      {:ok, _token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Token created and stored")
         |> assign(:token_form, token_form())
         |> assign(:show_token_form, false)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Invalid credentials")}

      {:error, {:unexpected_status, _status, %{"message" => message}}} ->
        {:noreply, put_flash(socket, :error, "Could not create token: #{message}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create token: #{inspect(reason)}")}
    end
  end

  defp format_ts(%DateTime{} = ts), do: Calendar.strftime(ts, "%Y-%m-%d %H:%M:%S UTC")
  defp format_ts(_), do: ""

  defp apply_action(socket, :new_service, _params) do
    if provider_validated?(socket.assigns.provider) do
      socket
      |> assign(:page_title, "New Service")
      |> assign(
        :service,
        %Service{
          provider_id: socket.assigns.provider.id,
          owner: default_owner(socket.assigns.provider)
        }
      )
    else
      socket
      |> put_flash(:error, "Validate the provider connection before managing services.")
      |> push_patch(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp apply_action(socket, :edit_service, %{"service_id" => service_id}) do
    if provider_validated?(socket.assigns.provider) do
      service = Services.get_service!(socket.assigns.current_scope, service_id)

      socket
      |> assign(:page_title, "Edit Service")
      |> assign(:service, service)
    else
      socket
      |> put_flash(:error, "Validate the provider connection before managing services.")
      |> push_patch(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, "Show Provider")
    |> assign(:service, nil)
  end

  defp page_title(:new_service), do: "New Service"
  defp page_title(:edit_service), do: "Edit Service"
  defp page_title(:show), do: "Show Provider"

  defp token_form do
    to_form(%{"username" => nil, "password" => nil, "name" => "service_hub_token"}, as: :token)
  end

  defp provider_validated?(%{last_validation_status: "ok"}), do: true
  defp provider_validated?(_), do: false

  defp default_owner(%{auth_data: auth_data, provider_type: %{key: "github"}}) do
    auth_data = auth_data || %{}

    Map.get(auth_data, "organization") || Map.get(auth_data, :organization)
  end

  defp default_owner(_), do: nil

  defp provider_key(%{provider_type: %{key: key}}), do: key
  defp provider_key(_), do: nil

  defp oauth_capable?(%{auth_type: %{key: key}, provider_type: %{key: "github"}})
       when key in ["github_oauth", "oauth"],
       do: true

  defp oauth_capable?(_), do: false

  defp oauth_button_label(%{auth_data: auth_data}) do
    auth_data = auth_data || %{}

    if Map.get(auth_data, "token") do
      "Reconnect OAuth"
    else
      "Connect with GitHub"
    end
  end
end
