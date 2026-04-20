defmodule ServiceHub.Notifications.NotificationChannel do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User

  schema "notification_channels" do
    field :provider, :string
    field :name, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :last_error, :string
    field :last_sent_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :provider, :name, :config]
  @cast_fields @required_fields ++ [:enabled, :last_error, :last_sent_at]

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:provider, ["telegram", "slack"])
    |> validate_config()
  end

  defp validate_config(changeset) do
    case get_field(changeset, :provider) do
      "slack" ->
        config = get_field(changeset, :config) || %{}

        if Map.has_key?(config, "webhook_url") do
          changeset
        else
          add_error(changeset, :config, "must include webhook_url for Slack")
        end

      _ ->
        changeset
    end
  end
end
