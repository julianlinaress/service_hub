defmodule ServiceHub.Providers.ProviderType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "provider_types" do
    field :name, :string
    field :key, :string
    field :required_fields, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(provider_type, attrs, _scope) do
    attrs
    |> normalize_required_fields()
    |> then(fn normalized_attrs ->
      provider_type
      |> cast(normalized_attrs, [:name, :key, :required_fields])
      |> validate_required([:name, :key])
      |> unique_constraint(:key, name: :provider_types_key_index)
    end)
  end

  defp normalize_required_fields(%{"required_fields" => ""} = attrs),
    do: Map.put(attrs, "required_fields", %{})

  defp normalize_required_fields(%{"required_fields" => value} = attrs) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> Map.put(attrs, "required_fields", map)
      _ -> attrs
    end
  end

  defp normalize_required_fields(%{required_fields: ""} = attrs),
    do: Map.put(attrs, :required_fields, %{})

  defp normalize_required_fields(%{required_fields: value} = attrs) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> Map.put(attrs, :required_fields, map)
      _ -> attrs
    end
  end

  defp normalize_required_fields(attrs), do: attrs
end
