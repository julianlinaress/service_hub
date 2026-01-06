defmodule ServiceHubWeb.NotificationLive.Index do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Notifications
  alias ServiceHub.Notifications.NotificationChannel

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Notification Channels
        <:subtitle>Configure Telegram and Slack channels for receiving alerts</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/config/notifications/new"}>
            <.icon name="hero-plus" /> New Channel
          </.button>
        </:actions>
      </.header>

      <.table id="channels" rows={@streams.channels}>
        <:col :let={{_id, channel}} label="Name">{channel.name}</:col>
        <:col :let={{_id, channel}} label="Provider">
          <span class="font-medium">{String.capitalize(channel.provider)}</span>
        </:col>
        <:col :let={{_id, channel}} label="Status">
          <%= if channel.enabled do %>
            <span class="text-success font-medium">Enabled</span>
          <% else %>
            <span class="text-secondary">Disabled</span>
          <% end %>
        </:col>
        <:col :let={{_id, channel}} label="Last Sent">
          {format_datetime(channel.last_sent_at)}
        </:col>
        <:col :let={{_id, channel}} label="Last Error">
          <%= if channel.last_error do %>
            <span class="text-error text-xs truncate max-w-xs" title={channel.last_error}>
              {String.slice(channel.last_error, 0, 50)}
            </span>
          <% else %>
            <span class="text-secondary">None</span>
          <% end %>
        </:col>
        <:action :let={{_id, channel}}>
          <.button
            variant="ghost"
            size="sm"
            phx-click="test_channel"
            phx-value-id={channel.id}
          >
            Test
          </.button>
        </:action>
        <:action :let={{_id, channel}}>
          <.button
            variant="ghost"
            size="sm"
            phx-click={JS.patch(~p"/config/notifications/#{channel}/edit")}
          >
            Edit
          </.button>
        </:action>
        <:action :let={{id, channel}}>
          <.button
            variant="ghost"
            size="sm"
            phx-click={JS.push("delete", value: %{id: channel.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.button>
        </:action>
      </.table>

      <div :if={@live_action in [:new, :edit]} class="mt-8">
        <.live_component
          module={ServiceHubWeb.NotificationLive.FormComponent}
          id={@channel.id || :new}
          title={@page_title}
          action={@live_action}
          channel={@channel}
          current_scope={@current_scope}
          patch={~p"/config/notifications"}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Notification Channels")
     |> stream(:channels, list_channels(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Channel")
    |> assign(:channel, Notifications.get_channel!(socket.assigns.current_scope, String.to_integer(id)))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Channel")
    |> assign(:channel, %NotificationChannel{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Notification Channels")
    |> assign(:channel, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    channel = Notifications.get_channel!(socket.assigns.current_scope, id)
    {:ok, _} = Notifications.delete_channel(socket.assigns.current_scope, channel)

    {:noreply, stream_delete(socket, :channels, channel)}
  end

  @impl true
  def handle_event("test_channel", %{"id" => id}, socket) do
    channel = Notifications.get_channel!(socket.assigns.current_scope, id)

    case test_channel_delivery(channel) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test notification sent successfully!")
         |> stream(:channels, list_channels(socket.assigns.current_scope), reset: true)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send test notification: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:channel_saved, channel}, socket) do
    {:noreply, stream_insert(socket, :channels, channel)}
  end

  defp list_channels(current_scope) do
    Notifications.list_channels(current_scope)
  end

  defp test_channel_delivery(channel) do
    # Send a test notification using the EventHandler
    test_event = %{
      name: "health.info",
      payload: %{
        "service_id" => 0,
        "deployment_id" => 0,
        "check_type" => "test",
        "message" => "Test notification from ServiceHub",
        "metadata" => %{
          "status" => "test",
          "host" => "test.example.com",
          "env" => "test"
        }
      },
      tags: %{
        "source" => "manual"
      }
    }

    # Deliver directly to this channel
    case deliver_test_to_channel(channel, test_event) do
      :ok -> {:ok, "Test notification sent"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_test_to_channel(channel, event) do
    payload = event.payload
    service_id = payload["service_id"]
    deployment_id = payload["deployment_id"]
    check_type = payload["check_type"]
    message = payload["message"]
    metadata = payload["metadata"]

    # Call the EventHandler's delivery logic directly
    case channel.provider do
      "telegram" ->
        ServiceHub.Notifications.EventHandler.send_telegram(
          channel.config,
          service_id,
          deployment_id,
          check_type,
          "info",
          message,
          metadata
        )

      "slack" ->
        ServiceHub.Notifications.EventHandler.send_slack(
          channel.config,
          service_id,
          deployment_id,
          check_type,
          "info",
          message,
          metadata
        )

      _ ->
        {:error, "Unknown provider: #{channel.provider}"}
    end
  rescue
    error ->
      {:error, inspect(error)}
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) do
    datetime
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end
end
