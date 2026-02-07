defmodule ServiceHub.Notifications.NotificationChannel do
  @moduledoc """
  A notification channel represents a delivery destination (Telegram, Slack, etc.)
  configured by a user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User
  alias ServiceHub.Notifications.TelegramAccount
  alias ServiceHub.Notifications.TelegramDestination

  schema "notification_channels" do
    field :provider, :string
    field :name, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :last_error, :string
    field :last_sent_at, :utc_datetime_usec

    belongs_to :user, User
    belongs_to :telegram_account, TelegramAccount
    belongs_to :telegram_destination, TelegramDestination

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :provider, :name, :config]
  @cast_fields @required_fields ++
                 [
                   :enabled,
                   :last_error,
                   :last_sent_at,
                   :telegram_account_id,
                   :telegram_destination_id
                 ]

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:provider, ["telegram", "slack"])
    |> validate_config()
  end

  defp validate_config(changeset) do
    provider = get_field(changeset, :provider)
    config = get_field(changeset, :config)

    case {provider, config} do
      {"telegram", %{"token" => _, "chat_id" => _}} ->
        changeset

      {"telegram", %{"token" => _, "chat_ref" => _}} ->
        changeset

      {"telegram", _} ->
        if has_telegram_references?(changeset) do
          changeset
        else
          add_error(
            changeset,
            :config,
            "must include token and chat_ref for Telegram, or linked telegram_account/telegram_destination"
          )
        end

      {"slack", %{"webhook_url" => _}} ->
        changeset

      {"slack", _} ->
        add_error(changeset, :config, "must include webhook_url for Slack")

      _ ->
        changeset
    end
  end

  defp has_telegram_references?(changeset) do
    get_field(changeset, :telegram_account_id) && get_field(changeset, :telegram_destination_id)
  end
end
