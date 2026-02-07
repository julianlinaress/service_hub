defmodule ServiceHubWeb.ServiceLive.NotificationRuleForm do
  use ServiceHubWeb, :live_component

  alias ServiceHub.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@form} id="rule-form" phx-target={@myself} phx-change="validate" phx-submit="save">
        <.input
          field={@form[:channel_id]}
          type="select"
          label="Notification Channel"
          prompt="Choose a channel"
          options={@channel_options}
          required
        />

        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

        <.input field={@form[:notify_on_manual]} type="checkbox" label="Notify on Manual Checks" />

        <div class="mt-4">
          <label class="label">
            <span class="label-text font-medium">Health Check Notifications</span>
          </label>
          <div class="space-y-2 pl-4">
            <.input
              name="service_notification_rule[rules][health][alert]"
              type="checkbox"
              label="Alert (service is down)"
              value={get_rule_value(@form, "health", "alert")}
            />
            <.input
              name="service_notification_rule[rules][health][warning]"
              type="checkbox"
              label="Warning (degraded service)"
              value={get_rule_value(@form, "health", "warning")}
            />
            <.input
              name="service_notification_rule[rules][health][recovery]"
              type="checkbox"
              label="Recovery (service is back up)"
              value={get_rule_value(@form, "health", "recovery")}
            />
            <.input
              name="service_notification_rule[rules][health][change]"
              type="checkbox"
              label="Info (status changes)"
              value={get_rule_value(@form, "health", "change")}
            />
          </div>
        </div>

        <div class="mt-4">
          <label class="label">
            <span class="label-text font-medium">Version Check Notifications</span>
          </label>
          <div class="space-y-2 pl-4">
            <.input
              name="service_notification_rule[rules][version][alert]"
              type="checkbox"
              label="Alert (version check failed)"
              value={get_rule_value(@form, "version", "alert")}
            />
            <.input
              name="service_notification_rule[rules][version][warning]"
              type="checkbox"
              label="Warning (version mismatch)"
              value={get_rule_value(@form, "version", "warning")}
            />
            <.input
              name="service_notification_rule[rules][version][change]"
              type="checkbox"
              label="Info (version changed)"
              value={get_rule_value(@form, "version", "change")}
            />
          </div>
        </div>

        <.input
          field={@form[:reminder_interval_minutes]}
          type="number"
          label="Reminder Interval (minutes)"
          placeholder="Optional - resend alerts every X minutes"
        />

        <div class="mt-6 flex items-center justify-end gap-x-4">
          <.button phx-disable-with="Saving..." variant="primary">Save Rule</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    channels = Notifications.list_channels(assigns.current_scope)

    channel_options =
      Enum.map(channels, fn channel ->
        {"#{channel.name} (#{channel.provider})", channel.id}
      end)

    changeset = Notifications.change_service_rule(assigns.current_scope, assigns.rule, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:channel_options, channel_options)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"service_notification_rule" => rule_params}, socket) do
    rule_params = normalize_rules(rule_params)

    changeset =
      Notifications.change_service_rule(
        socket.assigns.current_scope,
        socket.assigns.rule,
        rule_params
      )
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"service_notification_rule" => rule_params}, socket) do
    rule_params = normalize_rules(rule_params)
    save_rule(socket, socket.assigns.action, rule_params)
  end

  defp save_rule(socket, :edit, rule_params) do
    rule_params = convert_ids_to_integers(rule_params)

    case Notifications.update_service_rule(
           socket.assigns.current_scope,
           socket.assigns.rule,
           rule_params
         ) do
      {:ok, rule} ->
        notify_parent({:rule_saved, rule})

        {:noreply,
         socket
         |> put_flash(:info, "Notification rule updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update rule: #{inspect(reason)}")}
    end
  end

  defp save_rule(socket, :new, rule_params) do
    rule_params =
      rule_params
      |> Map.put("service_id", socket.assigns.service.id)
      |> convert_ids_to_integers()

    case Notifications.create_service_rule(socket.assigns.current_scope, rule_params) do
      {:ok, rule} ->
        notify_parent({:rule_saved, rule})

        {:noreply,
         socket
         |> put_flash(:info, "Notification rule created successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create rule: #{inspect(reason)}")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp normalize_rules(params) do
    case Map.get(params, "rules") do
      nil ->
        Map.put(params, "rules", %{})

      rules when is_map(rules) ->
        normalized_rules =
          rules
          |> Enum.map(fn {check_type, severities} ->
            normalized_severities =
              severities
              |> Enum.map(fn {severity, value} ->
                {severity, value == "on" || value == true || value == "true"}
              end)
              |> Enum.into(%{})

            {check_type, normalized_severities}
          end)
          |> Enum.into(%{})

        Map.put(params, "rules", normalized_rules)

      _ ->
        Map.put(params, "rules", %{})
    end
  end

  defp get_rule_value(form, check_type, severity) do
    case get_in(form.params, ["rules", check_type, severity]) do
      nil ->
        get_in(form.data.rules, [check_type, severity]) || false

      "on" ->
        true

      value when is_boolean(value) ->
        value

      "true" ->
        true

      _ ->
        false
    end
  end

  defp convert_ids_to_integers(params) do
    params
    |> maybe_convert_id("channel_id")
    |> maybe_convert_id("service_id")
    |> maybe_convert_id("reminder_interval_minutes")
  end

  defp maybe_convert_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {int, ""} -> Map.put(params, key, int)
          _ -> params
        end

      _ ->
        params
    end
  end

  defp notify_parent(msg), do: send(self(), msg)
end
