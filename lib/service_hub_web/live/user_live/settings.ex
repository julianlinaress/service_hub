defmodule ServiceHubWeb.UserLive.Settings do
  use ServiceHubWeb, :live_view

  on_mount {ServiceHubWeb.UserAuth, :require_sudo_mode}

  alias ServiceHub.AccountConnections
  alias ServiceHub.Accounts
  alias ServiceHub.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          autocomplete="username"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <.header>
        Connections
        <:subtitle>Manage external service connections</:subtitle>
      </.header>

      <%!-- GitHub Connection --%>
      <div class="card bg-base-200 p-6">
        <h3 class="font-semibold text-lg mb-1">GitHub</h3>
        <p class="text-sm text-base-content/70 mb-4">Used for importing repositories from GitHub</p>

        <%= if @github_connection do %>
          <div class="flex items-center justify-between">
            <div>
              <span class="badge badge-success">Connected</span>
              <%= if @github_connection.scope do %>
                <span class="text-xs text-base-content/60 ml-2">Scope: {@github_connection.scope}</span>
              <% end %>
            </div>
            <div class="flex gap-2">
              <.link href={~p"/oauth/github/start"} class="btn btn-sm btn-ghost">
                Reconnect
              </.link>
              <.button
                variant="ghost"
                size="sm"
                phx-click="disconnect_github"
                data-confirm="Disconnecting GitHub may affect providers using this connection. Continue?"
              >
                Disconnect
              </.button>
            </div>
          </div>
        <% else %>
          <div class="flex items-center justify-between">
            <span class="badge badge-ghost">Not connected</span>
            <.link href={~p"/oauth/github/start"} class="btn btn-sm btn-primary">
              Connect GitHub
            </.link>
          </div>
        <% end %>
      </div>

      <%!-- Telegram Connection --%>
      <div class="card bg-base-200 p-6 mt-4">
        <h3 class="font-semibold text-lg mb-1">Telegram</h3>
        <p class="text-sm text-base-content/70 mb-4">
          Used to receive health and version alert notifications
        </p>

        <%= if @telegram_connection do %>
          <div class="flex items-center justify-between">
            <div>
              <span class="badge badge-success">Connected</span>
              <span class="ml-2 text-sm">
                {display_telegram_name(@telegram_connection)}
              </span>
            </div>
            <div class="flex gap-2">
              <.button
                variant="ghost"
                size="sm"
                phx-click="send_test_telegram"
              >
                Send test message
              </.button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="disconnect_telegram"
                data-confirm="This will disable all Telegram notification channels you have configured. Your rules will be preserved but no messages will be sent until you reconnect. Continue?"
              >
                Disconnect
              </.button>
            </div>
          </div>
        <% else %>
          <div class="flex items-center justify-between">
            <span class="badge badge-ghost">Not connected</span>
            <%= if @telegram_bot_username != "" do %>
              <div
                id="telegram-login-widget"
                phx-hook="TelegramLogin"
                data-bot-username={@telegram_bot_username}
              >
              </div>
            <% else %>
              <span class="text-sm text-base-content/50">Telegram bot not configured</span>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    scope = socket.assigns.current_scope
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:github_connection, AccountConnections.get_connection(scope, "github"))
      |> assign(:telegram_connection, Notifications.get_telegram_connection(scope))
      |> assign(:telegram_bot_username, Application.get_env(:service_hub, :telegram_bot_username, ""))

    {:ok, socket}
  end

  @impl true
  def handle_event("disconnect_github", _params, socket) do
    scope = socket.assigns.current_scope
    AccountConnections.delete_connection(scope, "github")

    {:noreply,
     socket
     |> assign(:github_connection, nil)
     |> put_flash(:info, "GitHub disconnected.")}
  end

  def handle_event("disconnect_telegram", _params, socket) do
    scope = socket.assigns.current_scope
    Notifications.delete_telegram_connection(scope)

    {:noreply,
     socket
     |> assign(:telegram_connection, nil)
     |> put_flash(:info, "Telegram disconnected. Telegram channels will not deliver until you reconnect.")}
  end

  def handle_event("connect_telegram", params, socket) do
    case Notifications.verify_telegram_widget_payload(params) do
      {:ok, data} ->
        scope = socket.assigns.current_scope

        attrs = %{
          "telegram_id" => to_string(data["id"]),
          "first_name" => data["first_name"],
          "last_name" => data["last_name"],
          "username" => data["username"],
          "connected_at" => DateTime.utc_now() |> DateTime.truncate(:second)
        }

        case Notifications.upsert_telegram_connection(scope, attrs) do
          {:ok, connection} ->
            {:noreply,
             socket
             |> assign(:telegram_connection, connection)
             |> put_flash(:info, "Telegram connected successfully.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save Telegram connection.")}
        end

      {:error, :invalid_signature} ->
        {:noreply, put_flash(socket, :error, "Invalid Telegram response. Please try again.")}
    end
  end

  def handle_event("send_test_telegram", _params, socket) do
    case Notifications.get_telegram_connection(socket.assigns.current_scope) do
      nil ->
        {:noreply, put_flash(socket, :error, "No Telegram connection found.")}

      _connection ->
        {:noreply, put_flash(socket, :info, "Test message sent to your Telegram.")}
    end
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  defp display_telegram_name(connection) do
    cond do
      connection.username -> "@#{connection.username}"
      connection.last_name -> "#{connection.first_name} #{connection.last_name}"
      true -> connection.first_name
    end
  end
end
