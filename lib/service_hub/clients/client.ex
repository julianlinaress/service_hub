defmodule ServiceHub.Clients.Client do
  @moduledoc """
  Schema for Client (customer or institution).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "clients" do
    field :name, :string
    field :code, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> unique_constraint(:code)
  end
end
