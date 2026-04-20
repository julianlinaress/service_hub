defmodule ServiceHub.Notifications.TelegramConnections do
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.TelegramConnection
  alias ServiceHub.Repo

  @doc """
  Verifies a Telegram Login Widget payload using HMAC-SHA256.
  Returns {:ok, data} or {:error, :invalid_signature}.
  """
  def verify_widget_payload(params) when is_map(params) do
    bot_token = Application.get_env(:service_hub, :telegram_bot_token, "")
    {hash, data} = Map.pop(params, "hash")

    check_string =
      data
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)

    secret_key = :crypto.hash(:sha256, bot_token)

    expected =
      :crypto.mac(:hmac, :sha256, secret_key, check_string) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, hash || "") do
      {:ok, data}
    else
      {:error, :invalid_signature}
    end
  end

  def get_connection(%Scope{} = scope) do
    Repo.get_by(TelegramConnection, user_id: scope.user.id)
  end

  def get_connection_by_user_id(user_id) do
    Repo.get_by(TelegramConnection, user_id: user_id)
  end

  def upsert_connection(%Scope{} = scope, attrs) do
    attrs = Map.put(attrs, "user_id", scope.user.id)
    existing = get_connection(scope) || %TelegramConnection{}

    existing
    |> TelegramConnection.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def delete_connection(%Scope{} = scope) do
    case get_connection(scope) do
      nil -> {:ok, nil}
      connection -> Repo.delete(connection)
    end
  end
end
