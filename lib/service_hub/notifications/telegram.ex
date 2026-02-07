defmodule ServiceHub.Notifications.Telegram do
  @moduledoc """
  Telegram API helpers for bot validation and destination discovery.
  """

  @update_keys [
    "message",
    "edited_message",
    "channel_post",
    "edited_channel_post",
    "my_chat_member"
  ]

  @spec get_me(String.t()) :: {:ok, map()} | {:error, term()}
  def get_me(token) when is_binary(token) do
    request(token, "/getMe")
  end

  @spec get_updates(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_updates(token) when is_binary(token) do
    case request(token, "/getUpdates") do
      {:ok, result} when is_list(result) -> {:ok, result}
      {:ok, _} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec extract_destinations_from_updates([map()]) :: [map()]
  def extract_destinations_from_updates(updates) when is_list(updates) do
    updates
    |> Enum.flat_map(&extract_destinations_from_update/1)
    |> Enum.uniq_by(fn destination ->
      {destination.chat_ref, destination.message_thread_id}
    end)
  end

  defp extract_destinations_from_update(update) when is_map(update) do
    Enum.flat_map(@update_keys, fn key ->
      with payload when is_map(payload) <- Map.get(update, key),
           chat when is_map(chat) <- Map.get(payload, "chat") do
        [
          %{
            chat_ref: chat_ref(chat),
            chat_type: Map.get(chat, "type"),
            title: chat_title(chat),
            username: chat_username(chat),
            message_thread_id: Map.get(payload, "message_thread_id")
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp extract_destinations_from_update(_), do: []

  defp chat_ref(chat) do
    case chat_username(chat) do
      nil -> chat |> Map.get("id") |> to_string()
      username -> "@#{username}"
    end
  end

  defp chat_username(chat) do
    username = Map.get(chat, "username")
    if is_binary(username) and String.trim(username) != "", do: username, else: nil
  end

  defp chat_title(chat) do
    Map.get(chat, "title") ||
      [Map.get(chat, "first_name"), Map.get(chat, "last_name")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> case do
        "" -> nil
        value -> value
      end
  end

  defp request(token, endpoint) do
    url = "https://api.telegram.org/bot#{token}#{endpoint}"

    case http_client().request(method: :get, url: url) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_client do
    Application.get_env(:service_hub, :telegram_http_client, Req)
  end
end
