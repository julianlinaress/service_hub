defmodule ServiceHub.ProvidersTest do
  use ServiceHub.DataCase

  alias ServiceHub.Providers

  describe "providers" do
    alias ServiceHub.Providers.Provider

    import ServiceHub.AccountsFixtures, only: [user_scope_fixture: 0]
    import ServiceHub.ProvidersFixtures

    @invalid_attrs %{
      name: nil,
      base_url: nil,
      auth_data: nil,
      provider_type_id: nil,
      auth_type_id: nil
    }

    test "list_providers/1 returns all scoped providers" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      provider = provider_fixture(scope)
      other_provider = provider_fixture(other_scope)
      assert Providers.list_providers(scope) == [provider]
      assert Providers.list_providers(other_scope) == [other_provider]
    end

    test "get_provider!/2 returns the provider with given id" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)
      other_scope = user_scope_fixture()
      assert Providers.get_provider!(scope, provider.id) == provider

      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider!(other_scope, provider.id)
      end
    end

    test "create_provider/2 with valid data creates a provider" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)
      auth_type = auth_type_fixture(scope)

      valid_attrs = %{
        name: "some name",
        base_url: "https://example.com",
        provider_type_id: provider_type.id,
        auth_type_id: auth_type.id,
        auth_data: %{"token" => "abc"}
      }

      assert {:ok, %Provider{} = provider} = Providers.create_provider(scope, valid_attrs)
      assert provider.name == "some name"
      assert provider.base_url == "https://example.com"
      assert provider.auth_data == %{"token" => "abc"}
      assert provider.provider_type_id == provider_type.id
      assert provider.auth_type_id == auth_type.id
      assert provider.user_id == scope.user.id
    end

    test "create_provider/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Providers.create_provider(scope, @invalid_attrs)
    end

    test "update_provider/3 with valid data updates the provider" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      update_attrs = %{
        name: "some updated name",
        base_url: "https://other.example.com",
        auth_data: %{"token" => "updated"},
        provider_type_id: provider.provider_type_id,
        auth_type_id: provider.auth_type_id
      }

      assert {:ok, %Provider{} = provider} =
               Providers.update_provider(scope, provider, update_attrs)

      assert provider.name == "some updated name"
      assert provider.base_url == "https://other.example.com"
      assert provider.auth_data == %{"token" => "updated"}
    end

    test "update_provider/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      provider = provider_fixture(scope)

      assert_raise MatchError, fn ->
        Providers.update_provider(other_scope, provider, %{})
      end
    end

    test "update_provider/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Providers.update_provider(scope, provider, @invalid_attrs)

      assert provider == Providers.get_provider!(scope, provider.id)
    end

    test "delete_provider/2 deletes the provider" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)
      assert {:ok, %Provider{}} = Providers.delete_provider(scope, provider)
      assert_raise Ecto.NoResultsError, fn -> Providers.get_provider!(scope, provider.id) end
    end

    test "delete_provider/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      provider = provider_fixture(scope)
      assert_raise MatchError, fn -> Providers.delete_provider(other_scope, provider) end
    end

    test "change_provider/2 returns a provider changeset" do
      scope = user_scope_fixture()
      provider = provider_fixture(scope)
      assert %Ecto.Changeset{} = Providers.change_provider(scope, provider)
    end
  end

  describe "provider_types" do
    alias ServiceHub.Providers.ProviderType

    import ServiceHub.AccountsFixtures, only: [user_scope_fixture: 0]
    import ServiceHub.ProvidersFixtures

    @invalid_attrs %{name: nil, key: nil, required_fields: nil}

    test "list_provider_types/1 returns all provider_types" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope, %{name: "Gitea"})
      other_provider_type = provider_type_fixture(other_scope, %{name: "GitHub"})

      provider_type_ids =
        scope
        |> Providers.list_provider_types()
        |> Enum.map(& &1.id)

      assert provider_type.id in provider_type_ids
      assert other_provider_type.id in provider_type_ids
    end

    test "get_provider_type!/2 returns the provider_type with given id" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)
      other_scope = user_scope_fixture()
      assert Providers.get_provider_type!(scope, provider_type.id) == provider_type
      assert Providers.get_provider_type!(other_scope, provider_type.id) == provider_type
    end

    test "create_provider_type/2 with valid data creates a provider_type" do
      valid_attrs = %{name: "some name", key: "some key", required_fields: %{}}
      scope = user_scope_fixture()

      assert {:ok, %ProviderType{} = provider_type} =
               Providers.create_provider_type(scope, valid_attrs)

      assert provider_type.name == "some name"
      assert provider_type.key == "some key"
      assert provider_type.required_fields == %{}
    end

    test "create_provider_type/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Providers.create_provider_type(scope, @invalid_attrs)
    end

    test "update_provider_type/3 with valid data updates the provider_type" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)
      update_attrs = %{name: "some updated name", key: "some updated key", required_fields: %{}}

      assert {:ok, %ProviderType{} = provider_type} =
               Providers.update_provider_type(scope, provider_type, update_attrs)

      assert provider_type.name == "some updated name"
      assert provider_type.key == "some updated key"
      assert provider_type.required_fields == %{}
    end

    test "update_provider_type/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Providers.update_provider_type(scope, provider_type, @invalid_attrs)

      assert provider_type == Providers.get_provider_type!(scope, provider_type.id)
    end

    test "delete_provider_type/2 deletes the provider_type" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)
      assert {:ok, %ProviderType{}} = Providers.delete_provider_type(scope, provider_type)

      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider_type!(scope, provider_type.id)
      end
    end

    test "change_provider_type/2 returns a provider_type changeset" do
      scope = user_scope_fixture()
      provider_type = provider_type_fixture(scope)
      assert %Ecto.Changeset{} = Providers.change_provider_type(scope, provider_type)
    end
  end

  describe "auth_types" do
    alias ServiceHub.Providers.AuthType
    alias ServiceHub.Providers.AuthRegistry

    import ServiceHub.AccountsFixtures, only: [user_scope_fixture: 0]
    import ServiceHub.ProvidersFixtures

    @invalid_attrs %{name: nil, key: nil, required_fields: nil}

    test "list_auth_types/1 returns all auth_types" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)
      other_auth_type = auth_type_fixture(other_scope, %{key: "github_pat"})

      auth_type_keys =
        scope
        |> Providers.list_auth_types()
        |> Enum.map(& &1.key)

      assert auth_type.key in auth_type_keys
      assert other_auth_type.key in auth_type_keys
    end

    test "get_auth_type!/2 returns the auth_type with given id" do
      scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)
      other_scope = user_scope_fixture()
      assert Providers.get_auth_type!(scope, auth_type.id) == auth_type
      assert Providers.get_auth_type!(other_scope, auth_type.id) == auth_type
    end

    test "create_auth_type/2 with valid data creates a auth_type" do
      {:ok, %{name: name, required_fields: fields, compatible_providers: compatible_providers}} =
        AuthRegistry.fetch("token")

      valid_attrs = %{key: "token"}
      scope = user_scope_fixture()

      assert {:ok, %AuthType{} = auth_type} = Providers.create_auth_type(scope, valid_attrs)
      assert auth_type.name == name
      assert auth_type.key == "token"
      assert auth_type.required_fields == fields
      assert auth_type.compatible_providers == compatible_providers
    end

    test "create_auth_type/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Providers.create_auth_type(scope, @invalid_attrs)
    end

    test "update_auth_type/3 with valid data updates the auth_type" do
      scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)

      {:ok, %{name: name, required_fields: fields}} = AuthRegistry.fetch("github_pat")
      existing_compatible_providers = auth_type.compatible_providers

      update_attrs = %{key: "github_pat"}

      assert {:ok, %AuthType{} = auth_type} =
               Providers.update_auth_type(scope, auth_type, update_attrs)

      assert auth_type.name == name
      assert auth_type.key == "github_pat"
      assert auth_type.required_fields == fields
      assert auth_type.compatible_providers == existing_compatible_providers
    end

    test "update_auth_type/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Providers.update_auth_type(scope, auth_type, @invalid_attrs)

      assert auth_type == Providers.get_auth_type!(scope, auth_type.id)
    end

    test "delete_auth_type/2 deletes the auth_type" do
      scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)
      assert {:ok, %AuthType{}} = Providers.delete_auth_type(scope, auth_type)
      assert_raise Ecto.NoResultsError, fn -> Providers.get_auth_type!(scope, auth_type.id) end
    end

    test "change_auth_type/2 returns a auth_type changeset" do
      scope = user_scope_fixture()
      auth_type = auth_type_fixture(scope)
      assert %Ecto.Changeset{} = Providers.change_auth_type(scope, auth_type)
    end
  end
end
