defmodule ServiceHub.Notifications.EventHandler do
  @moduledoc """
  Notification delivery orchestration.

  Resolves channels from service notification rules, persists delivery attempts,
  and enqueues dedicated Oban jobs for provider delivery.
  """

  require Logger
  import Ecto.Query

  alias ServiceHub.Notifications.DeliveryAttempts
  alias ServiceHub.Notifications.NotificationChannel
  alias ServiceHub.Notifications.ServiceNotificationRule
  alias ServiceHub.Repo
  alias ServiceHub.Workers.NotificationDeliveryWorker

  @doc """
  Resolves target channels for an event, persists delivery attempts, and enqueues
  dedicated delivery jobs handled by Oban.
  """
  def enqueue_deliveries(event, opts \\ []) do
    event_name = Map.get(event, :name) || Map.get(event, "name")
    payload = Map.get(event, :payload) || Map.get(event, "payload") || %{}
    tags = Map.get(event, :tags) || Map.get(event, "tags") || %{}
    event_id = Map.get(event, :id) || Map.get(event, "id")

    if is_nil(event_id) do
      Logger.warning("Skipping delivery enqueue because event id is missing")
      :ok
    else
      service_id = Map.get(payload, "service_id")
      check_type = Map.get(payload, "check_type")
      severity = extract_severity(event_name)
      source = Map.get(tags, "source", "automatic")
      only_channel_id = Keyword.get(opts, :only_channel_id)

      channels =
        resolve_channels_for_delivery(
          service_id,
          check_type,
          severity,
          source,
          only_channel_id
        )

      Enum.each(channels, fn channel ->
        event_id
        |> maybe_upsert_attempt(channel, event)
        |> maybe_enqueue_delivery_job()
      end)

      :ok
    end
  end

  defp resolve_channels_for_delivery(
         _service_id,
         _check_type,
         _severity,
         _source,
         only_channel_id
       )
       when not is_nil(only_channel_id) do
    case parse_channel_id(only_channel_id) do
      nil -> []
      channel_id -> load_enabled_channel(channel_id)
    end
  end

  defp resolve_channels_for_delivery(service_id, check_type, severity, source, _only_channel_id) do
    load_applicable_rules(service_id, check_type, severity, source)
    |> Enum.map(& &1.channel)
  end

  defp load_enabled_channel(channel_id) do
    NotificationChannel
    |> where([channel], channel.id == ^channel_id and channel.enabled == true)
    |> Repo.all()
  end

  defp parse_channel_id(channel_id) when is_integer(channel_id), do: channel_id

  defp parse_channel_id(channel_id) when is_binary(channel_id) do
    case Integer.parse(channel_id) do
      {parsed_channel_id, ""} -> parsed_channel_id
      _ -> nil
    end
  end

  defp parse_channel_id(_), do: nil

  defp extract_severity(event_name) do
    cond do
      String.contains?(event_name, "alert") -> "alert"
      String.contains?(event_name, "warning") -> "warning"
      String.contains?(event_name, "recovery") -> "recovery"
      String.contains?(event_name, "info") -> "info"
      true -> "info"
    end
  end

  defp load_applicable_rules(service_id, check_type, severity, source) do
    now = DateTime.utc_now()

    ServiceNotificationRule
    |> join(:inner, [r], c in assoc(r, :channel))
    |> where([r, c], r.service_id == ^service_id)
    |> where([r, c], r.enabled == true and c.enabled == true)
    |> where([r], is_nil(r.mute_until) or r.mute_until < ^now)
    |> preload([r, c], channel: [])
    |> Repo.all()
    |> Enum.filter(fn rule ->
      rule_matches?(rule, check_type, severity, source)
    end)
  end

  defp rule_matches?(rule, check_type, severity, source) do
    if source == "manual" and not rule.notify_on_manual do
      false
    else
      check_rule_config(rule.rules, check_type, severity)
    end
  end

  defp check_rule_config(rules, check_type, severity) do
    case Map.get(rules, check_type) do
      nil -> false
      type_rules -> Map.get(type_rules, severity_to_rule_key(severity), false)
    end
  end

  defp severity_to_rule_key("info"), do: "change"
  defp severity_to_rule_key("warning"), do: "warning"
  defp severity_to_rule_key("alert"), do: "alert"
  defp severity_to_rule_key("recovery"), do: "recovery"
  defp severity_to_rule_key(_), do: "unknown"

  defp maybe_upsert_attempt(event_id, channel, event) do
    case DeliveryAttempts.upsert_pending_attempt(event_id, channel, event) do
      {:ok, attempt} ->
        attempt

      {:error, changeset} ->
        Logger.warning("Failed to upsert delivery attempt: #{inspect(changeset)}")
        nil
    end
  end

  defp maybe_enqueue_delivery_job(nil), do: :ok

  defp maybe_enqueue_delivery_job(attempt) do
    attempt
    |> delivery_job_changeset()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to enqueue notification delivery job: #{inspect(reason)}")
        :ok
    end
  end

  defp delivery_job_changeset(attempt) do
    %{attempt_id: attempt.id}
    |> NotificationDeliveryWorker.new(
      unique: [
        fields: [:worker, :args],
        keys: [:attempt_id],
        period: 86_400,
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
  end
end
