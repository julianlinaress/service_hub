defmodule ServiceHub.Notifications.TelegramConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User

  schema "user_telegram_connections" do
    field :telegram_id, :string
    field :first_name, :string
    field :last_name, :string
    field :username, :string
    field :connected_at, :utc_datetime

    belongs_to :user, User
    timestamps(type: :utc_datetime)
  end

  @required [:user_id, :telegram_id, :first_name, :connected_at]
  @optional [:last_name, :username]

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:user_id)
  end
end
