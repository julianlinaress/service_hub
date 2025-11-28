defmodule ServiceHub.Providers.AuthType do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Providers.AuthRegistry

  schema "auth_types" do
    field :name, :string
    field :key, :string
    field :required_fields, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(auth_type, attrs, _scope) do
    attrs
    |> then(fn normalized_attrs ->
      auth_type
      |> cast(normalized_attrs, [:name, :key])
      |> validate_required([:key])
      |> validate_change(:key, &validate_key/2)
      |> apply_registry_defaults()
      |> validate_required([:name])
      |> unique_constraint(:key, name: :auth_types_key_index)
    end)
  end

  defp validate_key(:key, key) do
    case AuthRegistry.fetch(key) do
      {:ok, _} -> []
      :error -> [key: "is not a supported auth type"]
    end
  end

  defp apply_registry_defaults(%Ecto.Changeset{} = changeset) do
    with key when is_binary(key) <- get_field(changeset, :key),
         {:ok, spec} <- AuthRegistry.fetch(key) do
      changeset
      |> put_change(:name, spec.name)
      |> put_change(:required_fields, spec.required_fields)
    else
      _ -> changeset
    end
  end
end
