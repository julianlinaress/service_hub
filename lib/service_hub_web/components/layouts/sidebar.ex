defmodule ServiceHubWeb.Layouts.Sidebar do
  @moduledoc """
  Sidebar navigation component for the dashboard layout.
  """
  use Phoenix.Component
  import ServiceHubWeb.CoreComponents

  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <aside class="drawer-side z-40">
      <label for="main-drawer" class="drawer-overlay"></label>
      <div class="bg-base-200 min-h-screen w-64 flex flex-col">
        <div class="p-4 border-b border-base-300">
          <.link navigate="/" class="flex items-center gap-2 text-xl font-bold">
            <.icon name="hero-server" class="w-6 h-6" />
            <span>Service Hub</span>
          </.link>
        </div>

        <nav class="flex-1 p-4 space-y-1">
          <.nav_item
            path="/"
            current_path={@current_path}
            icon="hero-squares-2x2"
            label="Dashboard"
          />

          <.nav_item
            path="/monitoring"
            current_path={@current_path}
            icon="hero-chart-bar"
            label="Monitoring"
          />

          <div class="pt-4">
            <div class="px-3 py-2 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
              Configuration
            </div>
            <.nav_item
              path="/config/providers"
              current_path={@current_path}
              icon="hero-cloud"
              label="Providers"
            />
            <.nav_item
              path="/config/services"
              current_path={@current_path}
              icon="hero-cube"
              label="Services"
            />
            <.nav_item
              path="/config/clients"
              current_path={@current_path}
              icon="hero-building-office"
              label="Clients"
            />
          </div>

          <div class="pt-4">
            <div class="px-3 py-2 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
              System
            </div>
            <.nav_item
              path="/config/provider-types"
              current_path={@current_path}
              icon="hero-cog-6-tooth"
              label="Provider Types"
            />
            <.nav_item
              path="/config/auth-types"
              current_path={@current_path}
              icon="hero-key"
              label="Auth Types"
            />
          </div>

          <div class="pt-4">
            <.nav_item
              path="/audit"
              current_path={@current_path}
              icon="hero-document-text"
              label="Audit Log"
            />
          </div>
        </nav>

        <div class="p-4 border-t border-base-300">
          <div class="flex items-center gap-3">
            <div class="avatar placeholder">
              <div class="bg-neutral text-neutral-content rounded-full w-10">
                <span class="text-sm"><%= user_initials(@current_scope.user) %></span>
              </div>
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate">
                <%= @current_scope.user.email %>
              </div>
              <.link href="/users/settings" class="text-xs text-base-content/60 hover:text-base-content">
                Settings
              </.link>
            </div>
            <.link
              href="/users/log-out"
              method="delete"
              class="btn btn-ghost btn-sm btn-square"
              title="Log out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
            </.link>
          </div>
        </div>
      </div>
    </aside>
    """
  end

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded-lg transition-colors",
        if(active?(@path, @current_path),
          do: "bg-primary text-primary-content font-medium",
          else: "text-base-content/80 hover:bg-base-300"
        )
      ]}
    >
      <.icon name={@icon} class="w-5 h-5" />
      <span><%= @label %></span>
    </.link>
    """
  end

  defp active?(path, current_path) do
    cond do
      path == "/" and current_path == "/" -> true
      path != "/" and String.starts_with?(current_path, path) -> true
      true -> false
    end
  end

  defp user_initials(user) do
    user.email
    |> String.split("@")
    |> List.first()
    |> String.slice(0..1)
    |> String.upcase()
  end
end
