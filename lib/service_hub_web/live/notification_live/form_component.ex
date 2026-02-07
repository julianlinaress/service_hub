defmodule ServiceHubWeb.NotificationLive.FormComponent do
  use ServiceHubWeb, :live_component

  alias ServiceHub.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure a notification channel</:subtitle>
      </.header>

      <.form
        for={@form}
        id="channel-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Channel Name" required />

        <.input
          field={@form[:provider]}
          type="select"
          label="Provider"
          prompt="Choose a provider"
          options={[{"Telegram", "telegram"}, {"Slack", "slack"}]}
          required
          phx-change="provider_changed"
          phx-target={@myself}
        />

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label="Enabled"
        />

        <div :if={@selected_provider == "telegram"} class="space-y-4">
          <p class="text-sm text-base-content/70">
            To set up Telegram notifications:
            <ol class="list-decimal list-inside mt-2 space-y-1">
              <li>
                Message <a href="https://t.me/BotFather" target="_blank" class="link">@BotFather</a>
                on Telegram
              </li>
              <li>Create a new bot and copy the token</li>
              <li>Add the bot to your group/channel</li>
              <li>
                Get your chat ID from
                <a
                  href="https://api.telegram.org/bot<YOUR-BOT-TOKEN>/getUpdates"
                  target="_blank"
                  class="link"
                >
                  getUpdates API
                </a>
              </li>
            </ol>
          </p>

          <.input
            name="notification_channel[config][token]"
            type="text"
            label="Bot Token"
            placeholder="123456:ABC-DEF..."
            value={get_config_value(@form, "token")}
            required={@selected_provider == "telegram"}
          />

          <.input
            name="notification_channel[config][chat_id]"
            type="text"
            label="Chat ID"
            placeholder="-1001234567890"
            value={get_config_value(@form, "chat_id")}
            required={@selected_provider == "telegram"}
          />

          <.input
            name="notification_channel[config][parse_mode]"
            type="select"
            label="Parse Mode"
            options={[{"HTML", "HTML"}, {"Markdown", "Markdown"}]}
            value={get_config_value(@form, "parse_mode") || "HTML"}
          />
        </div>

        <div :if={@selected_provider == "slack"} class="space-y-4">
          <p class="text-sm text-base-content/70">
            To set up Slack notifications:
            <ol class="list-decimal list-inside mt-2 space-y-1">
              <li>
                Go to <a href="https://api.slack.com/apps" target="_blank" class="link">Slack API</a>
              </li>
              <li>Create a new app or select existing one</li>
              <li>Enable "Incoming Webhooks"</li>
              <li>Create a webhook for your channel and copy the URL</li>
            </ol>
          </p>

          <.input
            name="notification_channel[config][webhook_url]"
            type="text"
            label="Webhook URL"
            placeholder="https://hooks.slack.com/services/..."
            value={get_config_value(@form, "webhook_url")}
            required={@selected_provider == "slack"}
          />
        </div>

        <div class="mt-6 flex items-center justify-end gap-x-4">
          <.button phx-disable-with="Saving..." variant="primary">Save Channel</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{channel: channel} = assigns, socket) do
    changeset = Notifications.change_channel(assigns.current_scope, channel, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_provider, channel.provider || "")
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event(
        "provider_changed",
        %{"notification_channel" => %{"provider" => provider}},
        socket
      ) do
    {:noreply, assign(socket, :selected_provider, provider)}
  end

  @impl true
  def handle_event("validate", %{"notification_channel" => channel_params}, socket) do
    changeset =
      Notifications.change_channel(
        socket.assigns.current_scope,
        socket.assigns.channel,
        channel_params
      )
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"notification_channel" => channel_params}, socket) do
    save_channel(socket, socket.assigns.action, channel_params)
  end

  defp save_channel(socket, :edit, channel_params) do
    case Notifications.update_channel(
           socket.assigns.current_scope,
           socket.assigns.channel,
           channel_params
         ) do
      {:ok, channel} ->
        notify_parent({:channel_saved, channel})

        {:noreply,
         socket
         |> put_flash(:info, "Channel updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_channel(socket, :new, channel_params) do
    case Notifications.create_channel(socket.assigns.current_scope, channel_params) do
      {:ok, channel} ->
        notify_parent({:channel_saved, channel})

        {:noreply,
         socket
         |> put_flash(:info, "Channel created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  # Helper to get config value from form params or data
  defp get_config_value(form, key) do
    # First try to get from params (submitted form data)
    case get_in(form.params, ["config", key]) do
      nil ->
        # Fall back to existing data
        get_in(form.data.config, [key]) || ""

      value ->
        value
    end
  end

  defp notify_parent(msg), do: send(self(), msg)
end
