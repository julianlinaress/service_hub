defmodule ServiceHub.Notifications.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :id

  schema "notification_events" do
    field :name, :string
    field :payload, :map, default: %{}
    field :tags, :map, default: %{}
    field :actor, :string
    field :source, :string

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :name, :payload, :tags, :actor, :source])
    |> validate_required([:id, :name])
    |> unique_constraint(:id, name: :notification_events_pkey)
  end
end
