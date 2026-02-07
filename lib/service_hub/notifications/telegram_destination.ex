defmodule ServiceHub.Notifications.TelegramDestination do
  @moduledoc """
  A Telegram destination (chat or channel) linked to a bot account.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Notifications.TelegramAccount

  schema "notification_telegram_destinations" do
    field :chat_ref, :string
    field :chat_type, :string
    field :title, :string
    field :username, :string
    field :message_thread_id, :integer
    field :verified_at, :utc_datetime_usec

    belongs_to :telegram_account, TelegramAccount

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:telegram_account_id, :chat_ref]
  @cast_fields @required_fields ++
                 [:chat_type, :title, :username, :message_thread_id, :verified_at]

  def changeset(destination, attrs) do
    destination
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:telegram_account_id, :chat_ref])
  end
end
