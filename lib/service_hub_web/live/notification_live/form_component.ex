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
              <li>Create a new bot and copy the token (or choose an existing connected bot)</li>
              <li>Send at least one message in the target chat or channel</li>
              <li>Click "Discover chats" to list available Telegram destinations</li>
            </ol>
          </p>

          <.input
            field={@form[:telegram_account_id]}
            type="select"
            label="Bot Account"
            prompt="Select connected bot account"
            options={telegram_account_options(@telegram_accounts)}
          />

          <.input
            name="notification_channel[config][token]"
            type="text"
            label="Bot Token (for new account)"
            placeholder="123456:ABC-DEF..."
            value={get_config_value(@form, "token")}
          />

          <.input
            field={@form[:telegram_destination_id]}
            type="select"
            label="Telegram Destination"
            prompt="Discover chats or choose a destination"
            options={telegram_destination_options(@telegram_destinations)}
          />

          <.input
            name="notification_channel[config][chat_ref]"
            type="text"
            label="Manual Chat Reference (optional fallback)"
            placeholder="@my_alerts or -1001234567890"
            value={get_config_value(@form, "chat_ref") || get_config_value(@form, "chat_id")}
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
          <.button
            :if={@selected_provider == "telegram"}
            type="submit"
            name="action"
            value="discover_chats"
            variant="ghost"
          >
            Discover chats
          </.button>
          <.button
            type="submit"
            name="action"
            value="save"
            phx-disable-with="Saving..."
            variant="primary"
          >
            Save Channel
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{channel: channel} = assigns, socket) do
    changeset = Notifications.change_channel(assigns.current_scope, channel, %{})

    telegram_accounts = Notifications.list_telegram_accounts(assigns.current_scope)

    telegram_destinations =
      if channel.telegram_account_id do
        Notifications.list_telegram_destinations(
          assigns.current_scope,
          channel.telegram_account_id
        )
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_provider, channel.provider || "")
     |> assign(:telegram_accounts, telegram_accounts)
     |> assign(:telegram_destinations, telegram_destinations)
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

    destinations =
      channel_params
      |> Map.get("telegram_account_id")
      |> case do
        nil ->
          []

        "" ->
          []

        account_id ->
          Notifications.list_telegram_destinations(socket.assigns.current_scope, account_id)
      end

    {:noreply,
     socket
     |> assign(:telegram_destinations, destinations)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"notification_channel" => channel_params} = params, socket) do
    case Map.get(params, "action", "save") do
      "discover_chats" ->
        discover_chats(socket, channel_params)

      _ ->
        save_channel(socket, socket.assigns.action, channel_params)
    end
  end

  defp discover_chats(socket, channel_params) do
    case Notifications.discover_telegram_destinations(
           socket.assigns.current_scope,
           channel_params
         ) do
      {:ok, account, destinations} ->
        channel_params =
          channel_params
          |> Map.put("telegram_account_id", to_string(account.id))
          |> maybe_set_first_destination(destinations)

        changeset =
          Notifications.change_channel(
            socket.assigns.current_scope,
            socket.assigns.channel,
            channel_params
          )
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(
           :telegram_accounts,
           Notifications.list_telegram_accounts(socket.assigns.current_scope)
         )
         |> assign(:telegram_destinations, destinations)
         |> assign_form(changeset)
         |> put_flash(:info, "Discovered #{length(destinations)} Telegram destination(s)")}

      {:error, :telegram_credentials_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Provide a bot token or select an existing bot account before discovering chats"
         )}

      {:error, :telegram_account_not_found} ->
        {:noreply, put_flash(socket, :error, "Selected Telegram account was not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to discover chats: #{inspect(reason)}")}
    end
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

  defp telegram_account_options(accounts) do
    Enum.map(accounts, fn account ->
      {"#{account.name} (##{account.id})", account.id}
    end)
  end

  defp telegram_destination_options(destinations) do
    Enum.map(destinations, fn destination ->
      label =
        [destination.title, destination.chat_ref]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" - ")

      {label, destination.id}
    end)
  end

  defp maybe_set_first_destination(params, [first | _]) do
    case Map.get(params, "telegram_destination_id") do
      nil -> Map.put(params, "telegram_destination_id", to_string(first.id))
      "" -> Map.put(params, "telegram_destination_id", to_string(first.id))
      _ -> params
    end
  end

  defp maybe_set_first_destination(params, []), do: params
end
