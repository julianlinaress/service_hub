defmodule ServiceHub.AccountConnections do
  import Ecto.Query, warn: false
  alias ServiceHub.Repo

  alias ServiceHub.AccountConnections.AccountConnection
  alias ServiceHub.Accounts.Scope

  def get_connection(%Scope{} = scope, provider_key) when is_binary(provider_key) do
    AccountConnection
    |> where(user_id: ^scope.user.id, provider_key: ^provider_key)
    |> Repo.one()
  end

  def upsert_connection(%Scope{} = scope, provider_key, attrs) when is_binary(provider_key) do
    existing = get_connection(scope, provider_key) || %AccountConnection{}

    attrs =
      attrs
      |> Map.put("provider_key", provider_key)

    existing
    |> AccountConnection.changeset(attrs, scope.user.id)
    |> Repo.insert_or_update()
  end
end
