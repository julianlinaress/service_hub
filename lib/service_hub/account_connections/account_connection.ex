defmodule ServiceHub.AccountConnections.AccountConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User

  schema "account_connections" do
    field :provider_key, :string
    field :token, :string
    field :refresh_token, :string
    field :scope, :string
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(account_connection, attrs, user_id) do
    account_connection
    |> cast(attrs, [:provider_key, :token, :refresh_token, :scope, :expires_at, :metadata])
    |> validate_required([:provider_key, :token])
    |> put_change(:user_id, user_id)
    |> unique_constraint(:provider_key, name: :account_connections_user_id_provider_key_index)
  end
end
