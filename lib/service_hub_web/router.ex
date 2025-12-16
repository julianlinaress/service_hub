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
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/providers", ProviderLive.Index, :index
      live "/providers/new", ProviderLive.Form, :new
      live "/providers/:id/services/new", ProviderLive.Show, :new_service
      live "/providers/:id/services/:service_id/edit", ProviderLive.Show, :edit_service
      live "/providers/:id", ProviderLive.Show, :show
      live "/providers/:id/edit", ProviderLive.Form, :edit
      live "/provider_types", ProviderTypeLive.Index, :index
      live "/provider_types/new", ProviderTypeLive.Form, :new
      live "/provider_types/:id", ProviderTypeLive.Show, :show
      live "/provider_types/:id/edit", ProviderTypeLive.Form, :edit
      live "/auth_types", AuthTypeLive.Index, :index
      live "/auth_types/new", AuthTypeLive.Form, :new
      live "/auth_types/:id", AuthTypeLive.Show, :show
      live "/auth_types/:id/edit", AuthTypeLive.Form, :edit
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
