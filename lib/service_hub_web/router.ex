defmodule ServiceHubWeb.Router do
  use ServiceHubWeb, :router

  import ServiceHubWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ServiceHubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ServiceHubWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", ServiceHubWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:service_hub, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ServiceHubWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/oauth/:provider/start", AccountOAuthController, :start
    get "/oauth/:provider/callback", AccountOAuthController, :callback
    get "/providers/:id/oauth/start", ProviderOAuthController, :start
    get "/providers/:id/oauth/callback", ProviderOAuthController, :callback

    live_session :require_authenticated_user,
      on_mount: [{ServiceHubWeb.UserAuth, :require_authenticated}] do
      # Main dashboard
      live "/dashboard", DashboardLive, :index

      # Monitoring (placeholder for future)
      # live "/monitoring", MonitoringLive, :index

      # Configuration section
      live "/config/providers", ProviderLive.Index, :index
      live "/config/providers/new", ProviderLive.Form, :new
      live "/config/providers/:id/edit", ProviderLive.Form, :edit

      # Provider dashboard with service management
      live "/providers/:id", ProviderLive.Dashboard, :show
      live "/providers/:provider_id/services/new", ServiceLive.Detail, :new
      live "/providers/:provider_id/services/:id", ServiceLive.Detail, :show
      live "/providers/:provider_id/services/:id/settings", ServiceLive.Detail, :edit

      # Services config (placeholder for future list view)
      # live "/config/services", ServiceLive.Index, :index

      # Clients config (placeholder for future)
      # live "/config/clients", ClientLive.Index, :index

      # System configuration
      live "/config/provider-types", ProviderTypeLive.Index, :index
      live "/config/provider-types/new", ProviderTypeLive.Form, :new
      live "/config/provider-types/:id", ProviderTypeLive.Show, :show
      live "/config/provider-types/:id/edit", ProviderTypeLive.Form, :edit
      live "/config/auth-types", AuthTypeLive.Index, :index
      live "/config/auth-types/new", AuthTypeLive.Form, :new
      live "/config/auth-types/:id", AuthTypeLive.Show, :show
      live "/config/auth-types/:id/edit", AuthTypeLive.Form, :edit

      # Notifications
      live "/config/notifications", NotificationLive.Index, :index
      live "/config/notifications/new", NotificationLive.Index, :new
      live "/config/notifications/:id/edit", NotificationLive.Index, :edit

      # User settings
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ServiceHubWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ServiceHubWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
