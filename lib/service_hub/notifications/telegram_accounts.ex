defmodule ServiceHub.Notifications.TelegramAccounts do
  @moduledoc false
  import Ecto.Query, warn: false
  import ServiceHub.Notifications.Helpers

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Notifications.Telegram
  alias ServiceHub.Notifications.TelegramAccount
  alias ServiceHub.Notifications.TelegramDestination
  alias ServiceHub.Repo

  def list_telegram_accounts(%Scope{} = scope) do
    TelegramAccount
    |> where([a], a.user_id == ^scope.user.id)
    |> order_by([a], asc: a.name, asc: a.id)
    |> Repo.all()
  end

  def list_telegram_destinations(%Scope{} = scope, account_id) do
    case get_telegram_account(scope, account_id) do
      nil ->
        []

      account ->
        TelegramDestination
        |> where([d], d.telegram_account_id == ^account.id)
        |> order_by([d], asc: d.title, asc: d.chat_ref)
        |> Repo.all()
    end
  end

  def discover_telegram_destinations(%Scope{} = scope, channel_attrs)
      when is_map(channel_attrs) do
    with {:ok, account} <- resolve_discovery_account(scope, channel_attrs),
         {:ok, _bot_info} <- Telegram.get_me(account.bot_token),
         {:ok, updates} <- Telegram.get_updates(account.bot_token) do
      updates
      |> Telegram.extract_destinations_from_updates()
      |> Enum.each(fn destination_attrs ->
        find_or_create_telegram_destination(account.id, destination_attrs)
      end)

      {:ok, account, list_telegram_destinations(scope, account.id)}
    end
  end

  def find_or_create_telegram_account(user_id, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      user_id: user_id,
      name: "Telegram Bot",
      bot_token: token,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      TelegramAccount,
      [attrs],
      on_conflict: [set: [updated_at: now]],
      conflict_target: [:user_id, :bot_token]
    )

    Repo.get_by!(TelegramAccount, user_id: user_id, bot_token: token)
  end

  def find_or_create_telegram_destination(account_id, chat_ref) when is_binary(chat_ref) do
    find_or_create_telegram_destination(account_id, %{chat_ref: chat_ref})
  end

  def find_or_create_telegram_destination(account_id, attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    chat_ref = get_value(attrs, "chat_ref")
    chat_type = get_value(attrs, "chat_type")
    title = get_value(attrs, "title")
    username = get_value(attrs, "username")
    thread_id = get_value(attrs, "message_thread_id")

    row = %{
      telegram_account_id: account_id,
      chat_ref: chat_ref,
      chat_type: chat_type,
      title: title,
      username: username,
      message_thread_id: thread_id,
      verified_at: now,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      TelegramDestination,
      [row],
      on_conflict: [
        set: [
          chat_type: chat_type,
          title: title,
          username: username,
          message_thread_id: thread_id,
          verified_at: now,
          updated_at: now
        ]
      ],
      conflict_target: [:telegram_account_id, :chat_ref]
    )

    Repo.get_by!(TelegramDestination, telegram_account_id: account_id, chat_ref: chat_ref)
  end

  defp resolve_discovery_account(%Scope{} = scope, channel_attrs) do
    config = get_value(channel_attrs, "config") || %{}
    token = get_value(config, "token")
    account_id = get_value(channel_attrs, "telegram_account_id")

    cond do
      present?(account_id) ->
        case get_telegram_account(scope, account_id) do
          nil -> {:error, :telegram_account_not_found}
          account -> {:ok, account}
        end

      present?(token) ->
        {:ok, find_or_create_telegram_account(scope.user.id, token)}

      true ->
        {:error, :telegram_credentials_required}
    end
  end

  defp get_telegram_account(%Scope{} = scope, account_id) do
    account_id = normalize_id(account_id)

    if is_nil(account_id) do
      nil
    else
      Repo.get_by(TelegramAccount, id: account_id, user_id: scope.user.id)
    end
  end
end
