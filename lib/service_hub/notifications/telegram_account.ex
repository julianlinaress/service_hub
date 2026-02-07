defmodule ServiceHub.Notifications.TelegramAccount do
  @moduledoc """
  Reusable Telegram bot credentials owned by a user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User

  schema "notification_telegram_accounts" do
    field :name, :string
    field :bot_token, :string
    field :last_validated_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :name, :bot_token]
  @cast_fields @required_fields ++ [:last_validated_at]

  def changeset(account, attrs) do
    account
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:bot_token, min: 20)
    |> unique_constraint([:user_id, :bot_token])
  end
end
