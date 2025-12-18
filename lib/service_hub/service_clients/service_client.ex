defmodule ServiceHub.ServiceClients.ServiceClient do
  @moduledoc """
  Schema for ServiceClient (installation of a service on a client).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Services.Service
  alias ServiceHub.Clients.Client

  schema "service_clients" do
    field :host, :string
    field :env, :string
    field :api_key, :string
    field :current_version, :string
    field :last_version_checked_at, :utc_datetime
    field :last_health_status, :string, default: "unknown"
    field :last_health_checked_at, :utc_datetime

    belongs_to :service, Service
    belongs_to :client, Client

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(service_client, attrs) do
    service_client
    |> cast(attrs, [
      :service_id,
      :client_id,
      :host,
      :env,
      :api_key,
      :current_version,
      :last_version_checked_at,
      :last_health_status,
      :last_health_checked_at
    ])
    |> validate_required([:service_id, :client_id, :host, :env])
    |> validate_inclusion(:last_health_status, ["unknown", "ok", "warning", "down"])
    |> foreign_key_constraint(:service_id)
    |> foreign_key_constraint(:client_id)
  end
end
