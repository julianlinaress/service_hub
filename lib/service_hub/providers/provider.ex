defmodule ServiceHub.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  alias ServiceHub.Accounts.User
  alias ServiceHub.Providers.AuthType
  alias ServiceHub.Providers.ProviderType

  schema "providers" do
    field :name, :string
    field :base_url, :string
    field :auth_data, :map, default: %{}
    field :last_validation_status, :string, default: "unvalidated"
    field :last_validated_at, :utc_datetime
    field :last_validation_error, :string
    belongs_to :user, User
    belongs_to :provider_type, ProviderType
    belongs_to :auth_type, AuthType

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs, user_scope) do
    attrs
    |> normalize_auth_data()
    |> then(fn normalized_attrs ->
      provider
      |> cast(normalized_attrs, [:name, :base_url, :auth_data, :provider_type_id, :auth_type_id])
      |> validate_required([:name, :base_url, :provider_type_id])
      |> assoc_constraint(:provider_type)
      |> assoc_constraint(:auth_type)
      |> put_change(:user_id, user_scope.user.id)
    end)
  end

  defp normalize_auth_data(%{"auth_data" => ""} = attrs), do: Map.put(attrs, "auth_data", %{})

  defp normalize_auth_data(%{"auth_data" => value} = attrs) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> Map.put(attrs, "auth_data", map)
      _ -> attrs
    end
  end

  defp normalize_auth_data(%{auth_data: ""} = attrs), do: Map.put(attrs, :auth_data, %{})

  defp normalize_auth_data(%{auth_data: value} = attrs) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> Map.put(attrs, :auth_data, map)
      _ -> attrs
    end
  end

  defp normalize_auth_data(attrs), do: attrs
end
