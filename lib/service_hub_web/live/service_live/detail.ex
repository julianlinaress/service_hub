defmodule ServiceHubWeb.ServiceLive.Detail do
  @moduledoc """
  Service dashboard view. Shows service info with a Settings entry point for edits.
  """
  use ServiceHubWeb, :live_view

  alias ServiceHub.{Deployments, Providers, Services}
  alias ServiceHub.Checks.{Health, Version}
  alias Phoenix.LiveView.JS
  alias ServiceHubWeb.Components.Status.HealthBadge
  alias ServiceHubWeb.Components.Status.VersionDisplay
  alias ServiceHubWeb.DeploymentLive.FormComponent, as: DeploymentForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/providers/#{@provider.id}"} class="btn btn-ghost btn-sm btn-square">
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
            <div>
              <h1 class="text-2xl font-bold">{@service.name || "Service"}</h1>
              <p class="text-sm text-base-content/60">{@provider.name}</p>
            </div>
          </div>

          <div class="flex gap-2">
            <.button
              :if={@live_action == :show}
              navigate={~p"/providers/#{@provider.id}/services/#{@service.id}/settings"}
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Settings
            </.button>
            <.button
              :if={@live_action == :new}
              navigate={~p"/providers/#{@provider.id}"}
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" /> Cancel
            </.button>
          </div>
        </div>

        <%= if @live_action == :new do %>
          <div class="rounded-lg border border-base-300 bg-base-100 p-4">
            <.live_component
              module={ServiceHubWeb.ServiceLive.FormComponent}
              id="service-form"
              action={@live_action}
              provider={@provider}
              service={@service}
              return_to={~p"/providers/#{@provider}"}
              current_scope={@current_scope}
            />
          </div>
        <% else %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div class="lg:col-span-2 space-y-4">
              <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                <h2 class="text-lg font-semibold mb-2">Repository</h2>
                <div class="text-sm text-base-content/70 font-mono">
                  {@service.owner}/{@service.repo}
                </div>
                <p class="text-sm text-base-content/60 mt-2">
                  Default ref: <span class="font-semibold">{@service.default_ref || "main"}</span>
                </p>
              </div>

              <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                <h2 class="text-lg font-semibold mb-2">Endpoints</h2>
                <div class="space-y-2 text-sm text-base-content/70">
                  <div>
                    <span class="font-semibold">Version template:</span>
                    <span class="font-mono">
                      {@service.version_endpoint_template || "https://{{host}}/api/version"}
                    </span>
                  </div>
                  <div>
                    <span class="font-semibold">Health template:</span>
                    <span class="font-mono">
                      {@service.healthcheck_endpoint_template || "https://{{host}}/api/health"}
                    </span>
                  </div>
                </div>
              </div>

            </div>

            <div class="space-y-4">
              <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                <div class="flex items-center justify-between mb-3">
                  <h2 class="text-lg font-semibold">Deployments</h2>
                  <.button variant="ghost" size="sm" phx-click="new-deployment">
                    <.icon name="hero-plus" class="w-4 h-4" /> Add deployment
                  </.button>
                </div>

                <div :if={Enum.empty?(@deployments)} class="text-sm text-base-content/60">
                  No deployments yet. Deployments will list here with version and health checks.
                </div>

                <div :if={!Enum.empty?(@deployments)} class="space-y-3">
                  <div
                    :for={deployment <- @deployments}
                    class="p-3 rounded-lg border border-base-200 bg-base-100/60"
                  >
                    <div class="flex items-center justify-between gap-2">
                      <div>
                        <p class="font-semibold">{deployment.name}</p>
                        <p class="text-xs text-base-content/60">
                          {deployment.env} · {deployment.host}
                        </p>
                      </div>
                      <HealthBadge.health_badge status={deployment.last_health_status} size="sm" />
                    </div>

                    <div class="flex items-center gap-2 mt-2 text-xs text-base-content/60">
                      <span class="font-semibold">Version:</span>
                      <VersionDisplay.version_display
                        version={deployment.current_version}
                        checked_at={deployment.last_version_checked_at}
                        size="sm"
                      />
                    </div>
                    <div class="flex items-center justify-between mt-2 text-xs text-base-content/60">
                      <div class="flex gap-2">
                        <.button
                          size="sm"
                          variant="ghost"
                          phx-click="edit-deployment"
                          phx-value-id={deployment.id}
                        >
                          <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Edit
                        </.button>
                        <.button
                          size="sm"
                          variant="ghost"
                          phx-click="check-health"
                          phx-value-id={deployment.id}
                          phx-disable-with="Checking..."
                        >
                          <.icon name="hero-heart-pulse" class="w-4 h-4" /> Health
                        </.button>
                        <.button
                          size="sm"
                          variant="ghost"
                          phx-click="check-version"
                          phx-value-id={deployment.id}
                          phx-disable-with="Checking..."
                        >
                          <.icon name="hero-arrow-path" class="w-4 h-4" /> Version
                        </.button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div
            :if={@live_action == :edit}
            id="service-settings"
            class="fixed inset-0 z-50 flex items-start justify-center bg-base-300/40 backdrop-blur-sm overflow-auto"
          >
            <div class="bg-base-100 border border-base-300 shadow-xl rounded-lg w-full max-w-3xl m-4">
              <div class="flex items-center justify-between p-4 border-b border-base-200">
                <h3 class="text-lg font-semibold">Service settings</h3>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click={hide_settings(@provider, @service)}
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
              <div class="p-4">
                <.live_component
                  module={ServiceHubWeb.ServiceLive.FormComponent}
                  id="service-form"
                  action={:edit}
                  provider={@provider}
                  service={@service}
                  return_to={~p"/providers/#{@provider.id}/services/#{@service.id}"}
                  current_scope={@current_scope}
                />
              </div>
            </div>
          </div>

          <div
            :if={@show_deployment_modal}
            id="deployment-modal"
            class="fixed inset-0 z-50 flex items-start justify-center bg-base-300/40 backdrop-blur-sm overflow-auto"
          >
            <div class="bg-base-100 border border-base-300 shadow-xl rounded-lg w-full max-w-3xl m-4">
              <div class="flex items-center justify-between p-4 border-b border-base-200">
                <h3 class="text-lg font-semibold">
                  {if @deployment_action == :new, do: "New deployment", else: "Edit deployment"}
                </h3>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="close-deployment-modal"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
              <div class="p-4">
                <.live_component
                  module={DeploymentForm}
                  id="deployment-form"
                  deployment={@deployment_form}
                  action={@deployment_action}
                  current_scope={@current_scope}
                />
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"provider_id" => provider_id} = params, _session, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, provider_id)

    {:ok,
     socket
     |> assign(:provider, provider)
     |> assign(:service, load_service(socket, params))
     |> assign(:deployments, [])
     |> assign(:show_deployment_modal, false)
     |> assign(:deployment_form, nil)
     |> assign(:deployment_action, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if provider_validated?(socket.assigns.provider) do
      socket
      |> assign(:page_title, "New Service")
      |> assign(:service, %Services.Service{provider_id: socket.assigns.provider.id})
    else
      socket
      |> put_flash(:error, "Validate the provider before adding services")
      |> push_navigate(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    service = Services.get_service!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, service.name || "Service")
    |> assign(:service, service)
    |> load_deployments()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if provider_validated?(socket.assigns.provider) do
      service = Services.get_service!(socket.assigns.current_scope, id)

      socket
      |> assign(:page_title, "Service Settings")
      |> assign(:service, service)
      |> load_deployments()
    else
      socket
      |> put_flash(:error, "Validate the provider before editing services")
      |> push_navigate(to: ~p"/providers/#{socket.assigns.provider}")
    end
  end

  defp load_service(socket, %{"id" => id}) do
    Services.get_service!(socket.assigns.current_scope, id)
  end

  defp load_service(_socket, _params) do
    %Services.Service{}
  end

  defp provider_validated?(provider) do
    provider.last_validation_status == "ok"
  end

  defp hide_settings(provider, service) do
    JS.patch(~p"/providers/#{provider.id}/services/#{service.id}")
  end

  defp load_deployments(socket) do
    deployments =
      Deployments.list_deployments_for_service(
        socket.assigns.current_scope,
        socket.assigns.service.id
      )

    assign(socket, :deployments, deployments)
  end

  @impl true
  def handle_event("check-health", %{"id" => id}, socket) do
    deployment = Deployments.get_deployment!(socket.assigns.current_scope, String.to_integer(id))

    case Health.run(deployment, socket.assigns.service) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> load_deployments()
         |> put_flash(:info, "Health check completed")}

      {:warning, reason, _deployment} ->
        {:noreply,
         socket
         |> load_deployments()
         |> put_flash(:error, "Health warning: #{format_reason(reason)}")}

      {:error, reason, _deployment} ->
        {:noreply,
         socket
         |> load_deployments()
         |> put_flash(:error, "Health check failed: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("check-version", %{"id" => id}, socket) do
    deployment = Deployments.get_deployment!(socket.assigns.current_scope, String.to_integer(id))

    case Version.run(deployment, socket.assigns.service) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> load_deployments()
         |> put_flash(:info, "Version check updated")}

      {:skipped, _deployment} ->
        {:noreply, put_flash(socket, :info, "Version check is disabled for this deployment")}

      {:error, reason, _deployment} ->
        {:noreply,
         socket
         |> load_deployments()
         |> put_flash(:error, "Version check failed: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("new-deployment", _params, socket) do
    deployment = %Deployments.Deployment{service_id: socket.assigns.service.id}

    {:noreply,
     socket
     |> assign(:deployment_form, deployment)
     |> assign(:deployment_action, :new)
     |> assign(:show_deployment_modal, true)}
  end

  @impl true
  def handle_event("edit-deployment", %{"id" => id}, socket) do
    deployment = Deployments.get_deployment!(socket.assigns.current_scope, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:deployment_form, deployment)
     |> assign(:deployment_action, :edit)
     |> assign(:show_deployment_modal, true)}
  end

  @impl true
  def handle_event("close-deployment-modal", _params, socket) do
    {:noreply, close_deployment_modal(socket)}
  end

  @impl true
  def handle_info({DeploymentForm, {:saved, _deployment}}, socket) do
    {:noreply,
     socket
     |> load_deployments()
     |> close_deployment_modal()}
  end

  @impl true
  def handle_info({:deployment_modal, :close}, socket) do
    {:noreply, close_deployment_modal(socket)}
  end

  defp format_reason({:unexpected_status, status}), do: "unexpected status #{status}"
  defp format_reason({:error, reason}), do: inspect(reason)
  defp format_reason(reason), do: inspect(reason)

  defp close_deployment_modal(socket) do
    assign(socket, show_deployment_modal: false, deployment_form: nil, deployment_action: nil)
  end
end
