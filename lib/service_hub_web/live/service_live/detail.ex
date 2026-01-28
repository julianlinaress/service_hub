defmodule ServiceHubWeb.ServiceLive.Detail do
  @moduledoc """
  Service dashboard view. Shows service info with a Settings entry point for edits.
  """
  use ServiceHubWeb, :live_view

  alias ServiceHub.{Deployments, Providers, Services}
  alias ServiceHub.Checks.{Health, Version, NotificationTrigger}
  alias ServiceHub.Deployments.PubSub, as: DeploymentPubSub
  alias Phoenix.LiveView.JS
  alias ServiceHubWeb.Components.Status.HealthBadge
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
              navigate={~p"/providers/#{@provider.id}/services/#{@service.id}/notifications"}
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-bell" class="w-4 h-4" /> Notifications
            </.button>
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
          <div class="space-y-4">
            <div class="rounded-lg border border-base-300 bg-base-100 p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div>
                    <h2 class="text-sm font-semibold text-base-content/60">Repository</h2>
                    <div class="text-base text-base-content font-mono">
                      {@service.owner}/{@service.repo}
                    </div>
                  </div>
                  <div class="divider divider-horizontal"></div>
                  <div>
                    <h2 class="text-sm font-semibold text-base-content/60">Default ref</h2>
                    <div class="text-base text-base-content font-semibold">
                      {@service.default_ref || "main"}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded-lg border border-base-300 bg-base-100 p-4">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold">Deployments</h2>
                <.button variant="primary" size="sm" phx-click="new-deployment">
                  <.icon name="hero-plus" class="w-4 h-4" /> Add deployment
                </.button>
              </div>

              <div :if={Enum.empty?(@deployments)} class="text-center py-12">
                <.icon name="hero-server-stack" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
                <p class="text-base-content/60">No deployments yet</p>
                <p class="text-sm text-base-content/40 mt-1">
                  Create a deployment to track health and version information
                </p>
              </div>

              <div :if={!Enum.empty?(@deployments)} class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <div
                  :for={deployment <- @deployments}
                  class="p-4 rounded-lg border border-base-200 bg-base-100 hover:border-base-300 transition-colors"
                >
                  <div class="flex items-start justify-between gap-3 mb-3">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-1">
                        <h3 class="font-semibold text-base truncate">{deployment.name}</h3>
                        <HealthBadge.health_badge status={deployment.last_health_status} size="sm" />
                      </div>
                      <div class="flex items-center gap-2 text-sm text-base-content/60 flex-wrap">
                        <span class="badge badge-ghost badge-sm">{deployment.env}</span>
                        <span class="truncate font-mono text-xs">{deployment.host}</span>
                        <span
                          :if={deployment.automatic_checks_enabled}
                          class="badge badge-info badge-sm gap-1"
                          title={"Auto-checks every #{format_interval(deployment.check_interval_minutes)}"}
                        >
                          <.icon name="hero-clock" class="w-3 h-3" />
                          Auto {format_interval(deployment.check_interval_minutes)}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div class="space-y-2 mb-3">
                    <div
                      :if={deployment.automatic_checks_enabled && Map.get(deployment, :next_check_at)}
                      class="flex items-center justify-between text-xs"
                    >
                      <span class="text-base-content/50">Next check</span>
                      <span
                        class="text-base-content/60 font-mono"
                        id={"next-check-#{deployment.id}"}
                        phx-hook="Countdown"
                        data-next-run-at={format_iso8601(Map.get(deployment, :next_check_at))}
                        data-server-utc={format_iso8601(@server_now)}
                      >
                        {Map.get(deployment, :next_check_in)}
                      </span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-xs font-semibold text-base-content/60">Version</span>
                      <code class={[
                        "text-xs font-mono",
                        if(deployment.current_version,
                          do: "text-base-content",
                          else: "text-base-content/40"
                        )
                      ]}>
                        {deployment.current_version || "Not checked"}
                      </code>
                    </div>
                    <div class="flex items-center justify-between text-xs">
                      <span class="text-base-content/50">Health checked</span>
                      <span class="text-base-content/60">
                        {format_relative_time(deployment.last_health_checked_at)}
                      </span>
                    </div>
                    <div
                      :if={deployment.version_check_enabled}
                      class="flex items-center justify-between text-xs"
                    >
                      <span class="text-base-content/50">Version checked</span>
                      <span class="text-base-content/60">
                        {format_relative_time(deployment.last_version_checked_at)}
                      </span>
                    </div>
                  </div>

                  <div class="flex items-center gap-2 pt-2 border-t border-base-200">
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
                      disabled={@checking_health == deployment.id}
                    >
                      <%= if @checking_health == deployment.id do %>
                        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" /> Checking...
                      <% else %>
                        <.icon name="hero-heart" class="w-4 h-4" /> Health
                      <% end %>
                    </.button>
                    <.button
                      size="sm"
                      variant="ghost"
                      phx-click="check-version"
                      phx-value-id={deployment.id}
                      disabled={@checking_version == deployment.id}
                    >
                      <%= if @checking_version == deployment.id do %>
                        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" /> Checking...
                      <% else %>
                        <.icon name="hero-arrow-path" class="w-4 h-4" /> Version
                      <% end %>
                    </.button>
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
            :if={@live_action == :notifications}
            id="notification-settings"
            class="fixed inset-0 z-50 flex items-start justify-center bg-base-300/40 backdrop-blur-sm overflow-auto"
          >
            <div class="bg-base-100 border border-base-300 shadow-xl rounded-lg w-full max-w-3xl m-4">
              <div class="flex items-center justify-between p-4 border-b border-base-200">
                <h3 class="text-lg font-semibold">Notification Settings</h3>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click={hide_notifications(@provider, @service)}
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
              <div class="p-4">
                <.live_component
                  module={ServiceHubWeb.ServiceLive.NotificationSettings}
                  id="notification-settings-component"
                  service={@service}
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
    service = load_service(socket, params)

    # Subscribe to deployment updates for this service
    if connected?(socket) and service do
      DeploymentPubSub.subscribe_service_deployments(service.id)
    end

    {:ok,
     socket
     |> assign(:provider, provider)
     |> assign(:service, service)
     |> assign(:deployments, [])
     |> assign(:show_deployment_modal, false)
     |> assign(:deployment_form, nil)
     |> assign(:deployment_action, nil)
     |> assign(:checking_health, nil)
     |> assign(:checking_version, nil)
     |> assign(:server_now, DateTime.utc_now(:second))}
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

  defp apply_action(socket, :notifications, %{"id" => id}) do
    service = Services.get_service!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Notification Settings")
    |> assign(:service, service)
    |> load_deployments()
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

  defp hide_notifications(provider, service) do
    JS.patch(~p"/providers/#{provider.id}/services/#{service.id}")
  end

  defp load_deployments(socket) do
    deployments =
      Deployments.list_deployments_for_service(
        socket.assigns.current_scope,
        socket.assigns.service.id
      )
      |> enrich_with_next_check_times()

    socket
    |> assign(:deployments, deployments)
    |> assign(:server_now, DateTime.utc_now(:second))
  end

  defp enrich_with_next_check_times(deployments) do
    import Ecto.Query
    alias ServiceHub.Automations.AutomationTarget
    alias ServiceHub.Repo

    # Get all deployment IDs
    deployment_ids = Enum.map(deployments, & &1.id)

    # Query automation_targets for next_run_at times
    next_checks =
      from(at in AutomationTarget,
        where: at.target_type == "deployment",
        where: at.target_id in ^deployment_ids,
        where: at.automation_id == "deployment_health",
        where: at.enabled == true,
        select: {at.target_id, at.next_run_at}
      )
      |> Repo.all()
      |> Map.new()

    # Enrich deployments with next check time
    Enum.map(deployments, fn deployment ->
      next_check_at = Map.get(next_checks, deployment.id)

      next_check_in =
        case next_check_at do
          nil -> nil
          next_run_at -> format_time_remaining(next_run_at)
        end

      deployment
      |> Map.put(:next_check_at, next_check_at)
      |> Map.put(:next_check_in, next_check_in)
    end)
  end

  defp format_time_remaining(nil), do: nil

  defp format_time_remaining(next_run_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(next_run_at, now)

    cond do
      diff_seconds < 0 ->
        "Running..."

      diff_seconds < 60 ->
        "< 1 min"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} min"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        minutes = rem(div(diff_seconds, 60), 60)

        if minutes > 0 do
          "#{hours}h #{minutes}m"
        else
          "#{hours}h"
        end

      true ->
        days = div(diff_seconds, 86400)
        "#{days}d"
    end
  end

  defp format_iso8601(nil), do: nil
  defp format_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_iso8601(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end
  defp format_iso8601(other), do: to_string(other)

  @impl true
  def handle_event("check-health", %{"id" => id}, socket) do
    deployment_id = String.to_integer(id)
    deployment = Deployments.get_deployment!(socket.assigns.current_scope, deployment_id)
    service = socket.assigns.service

    {:noreply,
     socket
     |> assign(:checking_health, deployment_id)
     |> start_async(:check_health, fn ->
       Health.run(deployment, service)
     end)}
  end

  @impl true
  def handle_event("check-version", %{"id" => id}, socket) do
    deployment_id = String.to_integer(id)
    deployment = Deployments.get_deployment!(socket.assigns.current_scope, deployment_id)
    service = socket.assigns.service

    {:noreply,
     socket
     |> assign(:checking_version, deployment_id)
     |> start_async(:check_version, fn ->
       Version.run(deployment, service)
     end)}
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

  def handle_event("stop-propagation", _params, socket) do
    {:noreply, socket}
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

  def handle_info({:rule_saved, _rule}, socket) do
    # Rule was saved by the notification settings component
    # No action needed in the parent LiveView
    {:noreply, socket}
  end

  @impl true
  def handle_info({:check_completed, %{service_id: service_id}}, socket) do
    # Only reload if this update is for our service
    if service_id == socket.assigns.service.id do
      {:noreply, load_deployments(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:check_health, {:ok, result}, socket) do
    # Get deployment from result (different positions for ok/warning/error)
    deployment =
      case result do
        {:ok, updated} -> updated
        {:warning, _reason, dep} -> dep
        {:error, _reason, dep} -> dep
      end

    # Trigger notifications for manual check
    NotificationTrigger.trigger_health_notification(deployment, result, "manual")

    case result do
      {:ok, updated} ->
        # Broadcast PubSub update
        DeploymentPubSub.broadcast_check_completed(updated, :health)

        {:noreply,
         socket
         |> assign(:checking_health, nil)
         |> load_deployments()
         |> put_flash(:info, "Health check completed")}

      {:warning, reason, deployment} ->
        # Broadcast PubSub update
        DeploymentPubSub.broadcast_check_completed(deployment, :health)

        {:noreply,
         socket
         |> assign(:checking_health, nil)
         |> load_deployments()
         |> put_flash(:error, "Health warning: #{format_reason(reason)}")}

      {:error, reason, deployment} ->
        # Broadcast PubSub update
        DeploymentPubSub.broadcast_check_completed(deployment, :health)

        {:noreply,
         socket
         |> assign(:checking_health, nil)
         |> load_deployments()
         |> put_flash(:error, "Health check failed: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_async(:check_health, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:checking_health, nil)
     |> put_flash(:error, "Health check crashed: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:check_version, {:ok, result}, socket) do
    # Get deployment from result
    deployment =
      case result do
        {:ok, updated} -> updated
        {:skipped, dep} -> dep
        {:error, _reason, dep} -> dep
      end

    # Trigger notifications for manual check
    NotificationTrigger.trigger_version_notification(deployment, result, "manual")

    case result do
      {:ok, updated} ->
        # Broadcast PubSub update
        DeploymentPubSub.broadcast_check_completed(updated, :version)

        {:noreply,
         socket
         |> assign(:checking_version, nil)
         |> load_deployments()
         |> put_flash(:info, "Version check updated")}

      {:skipped, deployment} ->
        # Broadcast PubSub update (even for skipped)
        DeploymentPubSub.broadcast_check_completed(deployment, :version)

        {:noreply,
         socket
         |> assign(:checking_version, nil)
         |> put_flash(:info, "Version check is disabled for this deployment")}

      {:error, reason, deployment} ->
        # Broadcast PubSub update
        DeploymentPubSub.broadcast_check_completed(deployment, :version)

        {:noreply,
         socket
         |> assign(:checking_version, nil)
         |> load_deployments()
         |> put_flash(:error, "Version check failed: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_async(:check_version, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:checking_version, nil)
     |> put_flash(:error, "Version check crashed: #{inspect(reason)}")}
  end

  defp format_reason({:unexpected_status, status}), do: "unexpected status #{status}"
  defp format_reason({:error, reason}), do: inspect(reason)
  defp format_reason(reason), do: inspect(reason)

  defp close_deployment_modal(socket) do
    assign(socket, show_deployment_modal: false, deployment_form: nil, deployment_action: nil)
  end

  defp format_relative_time(nil), do: "Never"

  defp format_relative_time(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} ->
        diff = DateTime.diff(DateTime.utc_now(), dt, :second)

        cond do
          diff < 60 -> "Just now"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          diff < 604_800 -> "#{div(diff, 86400)}d ago"
          true -> Calendar.strftime(dt, "%b %d, %Y")
        end

      _ ->
        "Unknown"
    end
  end

  defp format_interval(minutes) when minutes < 60, do: "#{minutes}m"
  defp format_interval(minutes) when minutes < 1440, do: "#{div(minutes, 60)}h"
  defp format_interval(1440), do: "24h"
  defp format_interval(minutes), do: "#{div(minutes, 60)}h"
end
