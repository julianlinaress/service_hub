defmodule ServiceHubWeb.ServiceLive.NotificationSettings do
  use ServiceHubWeb, :live_component

  alias ServiceHub.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-lg font-semibold">Notification Rules</h3>
          <p class="text-sm text-base-content/60">
            Configure which channels receive notifications for this service
          </p>
        </div>
        <.button variant="primary" size="sm" phx-click="new-rule" phx-target={@myself}>
          <.icon name="hero-plus" class="w-4 h-4" /> Add Rule
        </.button>
      </div>

      <div :if={@rules == []} class="text-center py-8">
        <.icon name="hero-bell-slash" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/60">No notification rules configured</p>
        <p class="text-sm text-base-content/40 mt-1">
          Add a rule to receive notifications for health checks and other events
        </p>
      </div>

      <div :if={@rules != []} class="space-y-3">
        <div
          :for={rule <- @rules}
          class="flex items-center justify-between p-4 bg-base-200/50 rounded-lg border border-base-300"
        >
          <div class="flex-1">
            <div class="flex items-center gap-2">
              <span class="font-medium">{rule.channel.name}</span>
              <span class="badge badge-sm">
                {rule.channel.provider}
              </span>
              <span :if={!rule.enabled} class="badge badge-sm badge-warning">
                Disabled
              </span>
              <span :if={rule.mute_until} class="badge badge-sm badge-error">
                Muted
              </span>
            </div>
            <div class="text-sm text-base-content/70 mt-1">
              {format_notification_types(rule.rules)}
            </div>
          </div>
          <div class="flex gap-2">
            <.button
              variant="ghost"
              size="sm"
              phx-click="edit-rule"
              phx-value-id={rule.id}
              phx-target={@myself}
            >
              Edit
            </.button>
            <.button
              variant="ghost"
              size="sm"
              phx-click="delete-rule"
              phx-value-id={rule.id}
              phx-target={@myself}
              data-confirm="Are you sure?"
            >
              Delete
            </.button>
          </div>
        </div>
      </div>

      <%!-- Rule Form Modal --%>
      <div
        :if={@show_rule_form}
        id="rule-form-modal"
        class="fixed inset-0 z-50 flex items-start justify-center bg-base-300/40 backdrop-blur-sm overflow-auto"
        phx-click="close-rule-form"
        phx-target={@myself}
      >
        <div
          class="bg-base-100 border border-base-300 shadow-xl rounded-lg w-full max-w-2xl m-4"
          phx-click="stop-propagation"
        >
          <div class="flex items-center justify-between p-4 border-b border-base-200">
            <h3 class="text-lg font-semibold">
              {if @rule_action == :new, do: "New Notification Rule", else: "Edit Notification Rule"}
            </h3>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="close-rule-form"
              phx-target={@myself}
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <div class="p-4">
            <.live_component
              module={ServiceHubWeb.ServiceLive.NotificationRuleForm}
              id="notification-rule-form"
              action={@rule_action}
              rule={@current_rule}
              service={@service}
              current_scope={@current_scope}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    service = assigns.service
    rules = Notifications.list_service_rules(assigns.current_scope, service.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:rules, rules)
     |> assign(:show_rule_form, false)
     |> assign(:rule_action, nil)
     |> assign(:current_rule, nil)}
  end

  @impl true
  def handle_event("new-rule", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_rule_form, true)
     |> assign(:rule_action, :new)
     |> assign(:current_rule, %Notifications.ServiceNotificationRule{
       service_id: socket.assigns.service.id
     })}
  end

  def handle_event("edit-rule", %{"id" => id}, socket) do
    {id, ""} = Integer.parse(id)
    rule = Notifications.get_service_rule!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:show_rule_form, true)
     |> assign(:rule_action, :edit)
     |> assign(:current_rule, rule)}
  end

  def handle_event("delete-rule", %{"id" => id}, socket) do
    {id, ""} = Integer.parse(id)
    rule = Notifications.get_service_rule!(socket.assigns.current_scope, id)
    {:ok, _} = Notifications.delete_service_rule(socket.assigns.current_scope, rule)

    # Reload rules
    rules =
      Notifications.list_service_rules(socket.assigns.current_scope, socket.assigns.service.id)

    {:noreply,
     socket
     |> put_flash(:info, "Notification rule deleted")
     |> assign(:rules, rules)}
  end

  def handle_event("close-rule-form", _params, socket) do
    {:noreply, assign(socket, :show_rule_form, false)}
  end

  def handle_event("stop-propagation", _params, socket) do
    {:noreply, socket}
  end

  def handle_info({:rule_saved, _rule}, socket) do
    # Reload rules
    rules =
      Notifications.list_service_rules(socket.assigns.current_scope, socket.assigns.service.id)

    {:noreply,
     socket
     |> assign(:rules, rules)
     |> assign(:show_rule_form, false)}
  end

  # Private Functions

  defp format_notification_types(rules) do
    types =
      Enum.flat_map(rules, fn {check_type, severities} ->
        enabled_severities =
          severities
          |> Enum.filter(fn {_severity, enabled} -> enabled end)
          |> Enum.map(fn {severity, _} -> severity end)

        if enabled_severities != [] do
          ["#{check_type}: #{Enum.join(enabled_severities, ", ")}"]
        else
          []
        end
      end)

    if types == [] do
      "No notifications configured"
    else
      Enum.join(types, " | ")
    end
  end
end
