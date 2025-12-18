defmodule ServiceHub.Providers.AuthType do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Providers.AuthRegistry

  schema "auth_types" do
    field :name, :string
    field :key, :string
    field :required_fields, :map, default: %{}
    field :compatible_providers, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(auth_type, attrs, _scope) do
    auth_type
    |> cast(attrs, [:name, :key, :compatible_providers])
    |> validate_required([:key])
    |> validate_change(:key, &validate_key/2)
    |> apply_registry_defaults()
    |> validate_required([:name])
    |> unique_constraint(:key, name: :auth_types_key_index)
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
      # Only apply registry defaults if no explicit value was provided
      |> then(fn cs ->
        if get_change(cs, :compatible_providers) == nil and
             get_field(cs, :compatible_providers) == [] do
          put_change(cs, :compatible_providers, spec[:compatible_providers] || [])
        else
          cs
        end
      end)
    else
      _ -> changeset
    end
  end
end
