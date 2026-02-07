defmodule ServiceHub.Notifications.EventHandler do
  @moduledoc """
  Event handler for routing health check and automation events to notification channels.

  This module receives internal notification events and delivers them to appropriate channels
  based on service notification rules.
  """

  require Logger
  import Ecto.Query

  alias ServiceHub.Notifications.ServiceNotificationRule
  alias ServiceHub.Repo

  @doc """
  Handles a notification event and routes it to configured channels.

  Expected event payload:
  - service_id: The service ID
  - deployment_id: Optional deployment ID
  - check_type: "health", "version", etc.
  - severity: "alert", "warning", "recovery", "info"
  - message: The notification message
  - metadata: Additional context
  """
  def handle_event(event) do
    %{
      name: event_name,
      payload: payload,
      tags: tags
    } = event

    service_id = Map.get(payload, "service_id")
    deployment_id = Map.get(payload, "deployment_id")
    check_type = Map.get(payload, "check_type")
    severity = extract_severity(event_name)
    message = Map.get(payload, "message")
    metadata = Map.get(payload, "metadata", %{})
    source = Map.get(tags, "source", "automatic")

    # Load applicable rules with channels
    rules = load_applicable_rules(service_id, check_type, severity, source)

    # Send to each channel
    Enum.each(rules, fn rule ->
      deliver_to_channel(
        rule.channel,
        service_id,
        deployment_id,
        check_type,
        severity,
        message,
        metadata
      )
    end)

    :ok
  end

  # Private Functions

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
    |> preload([r, c], channel: [:telegram_account, :telegram_destination])
    |> Repo.all()
    |> Enum.filter(fn rule ->
      rule_matches?(rule, check_type, severity, source)
    end)
  end

  defp rule_matches?(rule, check_type, severity, source) do
    # Check notify_on_manual
    if source == "manual" and not rule.notify_on_manual do
      false
    else
      # Check type-specific rules
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

  defp deliver_to_channel(
         channel,
         service_id,
         deployment_id,
         check_type,
         severity,
         message,
         metadata
       ) do
    case channel.provider do
      "telegram" ->
        send_telegram(
          channel,
          service_id,
          deployment_id,
          check_type,
          severity,
          message,
          metadata
        )

      "slack" ->
        send_slack(
          channel.config,
          service_id,
          deployment_id,
          check_type,
          severity,
          message,
          metadata
        )

      _ ->
        Logger.warning("Unknown provider: #{channel.provider}")
        :ok
    end
  rescue
    error ->
      Logger.error("Failed to deliver notification to channel #{channel.id}: #{inspect(error)}")

      # Update channel with last error
      update_channel_error(channel, inspect(error))

      :ok
  end

  def send_telegram(channel, _service_id, deployment_id, check_type, severity, message, metadata) do
    %{token: token, chat_ref: chat_ref, parse_mode: parse_mode, thread_id: thread_id} =
      resolve_telegram_delivery_config(channel)

    # Format message
    formatted_message =
      format_telegram_message(deployment_id, check_type, severity, message, metadata, parse_mode)

    # Send via Telegram Bot API
    url = "https://api.telegram.org/bot#{token}/sendMessage"

    request_payload = %{
      chat_id: chat_ref,
      text: formatted_message,
      parse_mode: parse_mode
    }

    request_payload =
      if is_nil(thread_id) do
        request_payload
      else
        Map.put(request_payload, :message_thread_id, thread_id)
      end

    case Req.post(url, json: request_payload) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, response} ->
        Logger.warning("Telegram API returned non-200: #{inspect(response)}")
        {:error, :telegram_api_error}

      {:error, reason} ->
        Logger.error("Failed to send Telegram message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp resolve_telegram_delivery_config(channel) do
    config = channel.config || %{}

    case {channel.telegram_account, channel.telegram_destination} do
      {%{bot_token: token}, %{chat_ref: chat_ref, message_thread_id: thread_id}} ->
        %{
          token: token,
          chat_ref: chat_ref,
          parse_mode: config["parse_mode"] || "HTML",
          thread_id: thread_id
        }

      _ ->
        %{
          token: config["token"],
          chat_ref: config["chat_ref"] || config["chat_id"],
          parse_mode: config["parse_mode"] || "HTML",
          thread_id: nil
        }
    end
  end

  def send_slack(config, _service_id, deployment_id, check_type, severity, message, metadata) do
    webhook_url = config["webhook_url"]

    # Format message
    formatted_message =
      format_slack_message(deployment_id, check_type, severity, message, metadata)

    # Send via Slack webhook
    case Req.post(webhook_url, json: formatted_message) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, response} ->
        Logger.warning("Slack webhook returned non-200: #{inspect(response)}")
        {:error, :slack_webhook_error}

      {:error, reason} ->
        Logger.error("Failed to send Slack message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_telegram_message(deployment_id, check_type, severity, message, metadata, parse_mode) do
    emoji = severity_emoji(severity)
    host = Map.get(metadata, "host", "unknown")
    env = Map.get(metadata, "env", "unknown")

    if parse_mode == "HTML" do
      """
      #{emoji} <b>#{String.upcase(severity)}</b>

      <b>Check:</b> #{check_type}
      <b>Deployment:</b> #{deployment_id}
      <b>Host:</b> #{host}
      <b>Env:</b> #{env}

      #{message}
      """
    else
      """
      #{emoji} *#{String.upcase(severity)}*

      *Check:* #{check_type}
      *Deployment:* #{deployment_id}
      *Host:* #{host}
      *Env:* #{env}

      #{message}
      """
    end
  end

  defp format_slack_message(deployment_id, check_type, severity, message, metadata) do
    emoji = severity_emoji(severity)
    host = Map.get(metadata, "host", "unknown")
    env = Map.get(metadata, "env", "unknown")
    color = severity_color(severity)

    %{
      text: "#{emoji} #{String.upcase(severity)}: #{message}",
      attachments: [
        %{
          color: color,
          fields: [
            %{title: "Check", value: check_type, short: true},
            %{title: "Deployment", value: to_string(deployment_id), short: true},
            %{title: "Host", value: host, short: true},
            %{title: "Env", value: env, short: true}
          ]
        }
      ]
    }
  end

  defp severity_emoji("alert"), do: "🚨"
  defp severity_emoji("warning"), do: "⚠️"
  defp severity_emoji("recovery"), do: "✅"
  defp severity_emoji("info"), do: "ℹ️"
  defp severity_emoji(_), do: "📢"

  defp severity_color("alert"), do: "danger"
  defp severity_color("warning"), do: "warning"
  defp severity_color("recovery"), do: "good"
  defp severity_color(_), do: "#36a64f"

  defp update_channel_error(channel, error_message) do
    changeset =
      Ecto.Changeset.change(channel, %{
        last_error: error_message,
        last_sent_at: DateTime.utc_now()
      })

    Repo.update(changeset)
  end
end
