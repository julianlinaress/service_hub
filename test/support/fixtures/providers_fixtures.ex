defmodule ServiceHub.ProvidersFixtures do
  def provider_fixture(scope, attrs \\ %{}) do
    provider_type = Map.get_lazy(attrs, :provider_type, fn -> provider_type_fixture(scope) end)
    auth_type = Map.get_lazy(attrs, :auth_type, fn -> auth_type_fixture(scope) end)

    attrs =
      attrs
      |> Map.delete(:provider_type)
      |> Map.delete(:auth_type)
      |> Enum.into(%{
        auth_data: %{"token" => "secret"},
        auth_type_id: auth_type.id,
        base_url: "https://provider.test",
        name: "some name",
        provider_type_id: provider_type.id
      })

    {:ok, provider} =
      ServiceHub.Providers.create_provider(scope, attrs)
      |> case do
        {:ok, provider} -> {:ok, ServiceHub.Repo.preload(provider, [:provider_type, :auth_type])}
        other -> other
      end

    provider
  end

  @doc """
  Generate a provider_type.
  """
  def provider_type_fixture(scope, attrs \\ %{}) do
    defaults = %{
      key: "gitea-#{System.unique_integer([:positive])}",
      name: "Gitea",
      required_fields: %{"owner" => %{"label" => "Owner", "type" => "text"}}
    }

    attrs = Enum.into(attrs, defaults)

    {:ok, provider_type} = ServiceHub.Providers.create_provider_type(scope, attrs)
    provider_type
  end

  @doc """
  Generate a auth_type.
  """
  def auth_type_fixture(scope, attrs \\ %{}) do
    defaults = %{
      key: "pat-#{System.unique_integer([:positive])}",
      name: "Personal Access Token",
      required_fields: %{"token" => %{"label" => "Token", "type" => "password"}}
    }

    attrs = Enum.into(attrs, defaults)

    {:ok, auth_type} = ServiceHub.Providers.create_auth_type(scope, attrs)
    auth_type
  end
end
