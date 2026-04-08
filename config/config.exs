# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :service_hub, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [
    default: 10,
    health_checks: 20,
    version_checks: 10,
    notifications: 5,
    maintenance: 1
  ],
  plugins: [
    {Oban.Plugins.Cron, crontab: []},
    {Oban.Plugins.Pruner, max_age: 86_400}
  ],
  repo: ServiceHub.Repo

config :service_hub, :scopes,
  user: [
    default: true,
    module: ServiceHub.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ServiceHub.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :service_hub,
  ecto_repos: [ServiceHub.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure automations
config :service_hub, ServiceHub.Automations.Scheduler,
  poll_interval_ms: 10_000,
  poll_jitter_ms: 10_000,
  batch_size: 50,
  global_concurrency: 10,
  lease_ttl_min_minutes: 10,
  lease_ttl_multiplier: 2

config :service_hub, ServiceHub.Automations,
  automations: [
    ServiceHub.Automations.HealthCheck,
    ServiceHub.Automations.VersionCheck,
    ServiceHub.Automations.RetentionCleaner
  ]

# Configure the endpoint
config :service_hub, ServiceHubWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ServiceHubWeb.ErrorHTML, json: ServiceHubWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ServiceHub.PubSub,
  live_view: [signing_salt: "zq0eYO5e"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :service_hub, ServiceHub.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  service_hub: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  service_hub: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
