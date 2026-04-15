defmodule ServiceHub.Notifications.DeliveryAttempts do
  @moduledoc """
  Persistence helpers for notification delivery attempts.
  """

  alias ServiceHub.Notifications.DeliveryAttempt
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.TelegramAccount
  alias ServiceHub.Notifications.TelegramDestination
  alias ServiceHub.Repo

  @spec upsert_pending_attempt(String.t() | nil, NotificationChannel.t(), map()) ::
          {:ok, DeliveryAttempt.t() | nil} | {:error, Ecto.Changeset.t()}
  def upsert_pending_attempt(nil, _channel, _event), do: {:ok, nil}

  def upsert_pending_attempt(event_id, %NotificationChannel{} = channel, event)
      when is_binary(event_id) and is_map(event) do
    channel = preload_delivery_relations(channel)
    delivery_attempt_key = "#{event_id}:#{channel.id}"

    attrs = %{
      event_id: event_id,
      channel_id: channel.id,
      provider: channel.provider,
      status: "pending",
      payload_snapshot: build_payload_snapshot(event),
      destination_snapshot: build_destination_snapshot(channel),
      destination_ref: extract_destination_ref(channel),
      delivery_attempt_key: delivery_attempt_key
    }

    %DeliveryAttempt{}
    |> DeliveryAttempt.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]],
      conflict_target: [:delivery_attempt_key]
    )
    |> case do
      {:ok, attempt} -> {:ok, attempt}
      {:error, _changeset} = error -> error
    end
  end

  @spec mark_attempt_started(DeliveryAttempt.t(), non_neg_integer() | nil) ::
          {:ok, DeliveryAttempt.t()} | {:error, Ecto.Changeset.t()}
  def mark_attempt_started(%DeliveryAttempt{} = attempt, attempt_count \\ nil, oban_job_id \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      status: "in_progress",
      attempted_at: now,
      attempt_count: attempt_count || max(attempt.attempt_count, 0) + 1,
      oban_job_id: oban_job_id || attempt.oban_job_id
    }

    attempt
    |> DeliveryAttempt.changeset(attrs)
    |> Repo.update()
  end

  @spec mark_attempt_delivered(DeliveryAttempt.t(), map()) ::
          {:ok, DeliveryAttempt.t()} | {:error, Ecto.Changeset.t()}
  def mark_attempt_delivered(%DeliveryAttempt{} = attempt, response \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      status: "delivered",
      provider_message_id: extract_provider_message_id(response),
      provider_response_code: extract_provider_response_code(response),
      provider_response: normalize_response(response),
      error_code: nil,
      error_message: nil,
      delivered_at: now
    }

    attempt
    |> DeliveryAttempt.changeset(attrs)
    |> Repo.update()
  end

  @spec mark_attempt_failed(DeliveryAttempt.t(), term(), map()) ::
          {:ok, DeliveryAttempt.t()} | {:error, Ecto.Changeset.t()}
  def mark_attempt_failed(%DeliveryAttempt{} = attempt, reason, response \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {error_code, error_message} = normalize_reason(reason)

    attrs = %{
      status: "failed",
      provider_response_code: extract_provider_response_code(response),
      provider_response: normalize_response(response),
      error_code: error_code,
      error_message: error_message,
      failed_at: now
    }

    attempt
    |> DeliveryAttempt.changeset(attrs)
    |> Repo.update()
  end

  @spec get_attempt(integer() | String.t()) :: DeliveryAttempt.t() | nil
  def get_attempt(id) when is_integer(id) do
    case Repo.get(DeliveryAttempt, id) do
      nil -> nil
      attempt -> Repo.preload(attempt, :channel)
    end
  end

  def get_attempt(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} -> get_attempt(parsed_id)
      _ -> nil
    end
  end

  defp build_payload_snapshot(event) do
    %{
      "id" => Map.get(event, :id) || Map.get(event, "id"),
      "name" => Map.get(event, :name) || Map.get(event, "name"),
      "payload" => Map.get(event, :payload) || Map.get(event, "payload") || %{},
      "tags" => Map.get(event, :tags) || Map.get(event, "tags") || %{}
    }
  end

  defp build_destination_snapshot(%NotificationChannel{} = channel) do
    %{
      "channel_id" => channel.id,
      "channel_name" => channel.name,
      "provider" => channel.provider,
      "config" => channel.config || %{},
      "telegram_account_id" => channel.telegram_account_id,
      "telegram_destination_id" => channel.telegram_destination_id,
      "resolved_destination" => resolve_destination(channel)
    }
  end

  defp resolve_destination(%NotificationChannel{provider: "telegram"} = channel) do
    config = channel.config || %{}

    token =
      case channel.telegram_account do
        %TelegramAccount{bot_token: bot_token} -> bot_token
        _ -> config["token"]
      end

    {chat_ref, thread_id} =
      case channel.telegram_destination do
        %TelegramDestination{chat_ref: destination_chat_ref, message_thread_id: message_thread_id} ->
          {destination_chat_ref, message_thread_id}

        _ ->
          {config["chat_ref"] || config["chat_id"], nil}
      end

    base = %{
      "token" => token,
      "chat_ref" => chat_ref,
      "parse_mode" => config["parse_mode"] || "HTML"
    }

    if is_nil(thread_id) do
      base
    else
      Map.put(base, "thread_id", thread_id)
    end
  end

  defp resolve_destination(%NotificationChannel{provider: "slack"} = channel) do
    %{
      "webhook_url" => channel.config["webhook_url"]
    }
  end

  defp resolve_destination(_channel), do: %{}

  defp extract_destination_ref(%NotificationChannel{provider: "telegram"} = channel) do
    destination_chat_ref =
      case channel.telegram_destination do
        %{chat_ref: chat_ref} -> chat_ref
        _ -> nil
      end

    destination_chat_ref || channel.config["chat_ref"] || channel.config["chat_id"]
  end

  defp extract_destination_ref(%NotificationChannel{provider: "slack"} = channel) do
    channel.config["webhook_url"]
  end

  defp extract_destination_ref(_channel), do: nil

  defp normalize_reason({:error, message}) when is_binary(message), do: {"error", message}

  defp normalize_reason(reason) when is_map(reason) do
    code = reason[:error_code] || reason["error_code"] || "delivery_failed"
    message = reason[:error_message] || reason["error_message"] || inspect(reason)

    {to_string(code), to_string(message)}
  end

  defp normalize_reason(reason) when is_atom(reason),
    do: {Atom.to_string(reason), inspect(reason)}

  defp normalize_reason(reason), do: {"delivery_failed", inspect(reason)}

  defp extract_provider_message_id(%{"provider_message_id" => value}), do: to_string(value)
  defp extract_provider_message_id(%{provider_message_id: value}), do: to_string(value)
  defp extract_provider_message_id(_), do: nil

  defp extract_provider_response_code(%{"provider_response_code" => value}), do: to_string(value)
  defp extract_provider_response_code(%{provider_response_code: value}), do: to_string(value)
  defp extract_provider_response_code(%{"status" => value}), do: to_string(value)
  defp extract_provider_response_code(%{status: value}), do: to_string(value)
  defp extract_provider_response_code(_), do: nil

  defp normalize_response(response) when is_map(response), do: response
  defp normalize_response(_), do: %{}

  defp preload_delivery_relations(%NotificationChannel{} = channel) do
    Repo.preload(channel, [:telegram_account, :telegram_destination])
  end
end
