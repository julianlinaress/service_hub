defmodule ServiceHub.Providers do
  import Ecto.Query, warn: false
  alias ServiceHub.Repo

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Providers.{AuthType, Provider, ProviderType}

  def subscribe_providers(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ServiceHub.PubSub, "user:#{key}:providers")
  end

  defp broadcast_provider(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ServiceHub.PubSub, "user:#{key}:providers", message)
  end

  def list_providers(%Scope{} = scope) do
    Provider
    |> where(user_id: ^scope.user.id)
    |> preload([:provider_type, :auth_type])
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def get_provider!(%Scope{} = scope, id) do
    Provider
    |> where(id: ^id, user_id: ^scope.user.id)
    |> preload([:provider_type, :auth_type])
    |> Repo.one!()
  end

  def create_provider(%Scope{} = scope, attrs) do
    with {:ok, provider = %Provider{}} <-
           %Provider{}
           |> Provider.changeset(attrs, scope)
           |> Repo.insert() do
      provider = Repo.preload(provider, [:provider_type, :auth_type])
      broadcast_provider(scope, {:created, provider})
      {:ok, provider}
    end
  end

  def update_provider(%Scope{} = scope, %Provider{} = provider, attrs) do
    true = provider.user_id == scope.user.id

    with {:ok, provider = %Provider{}} <-
           provider
           |> Provider.changeset(attrs, scope)
           |> Repo.update() do
      provider = Repo.preload(provider, [:provider_type, :auth_type])
      broadcast_provider(scope, {:updated, provider})
      {:ok, provider}
    end
  end

  def delete_provider(%Scope{} = scope, %Provider{} = provider) do
    true = provider.user_id == scope.user.id

    with {:ok, provider = %Provider{}} <-
           Repo.delete(provider) do
      broadcast_provider(scope, {:deleted, provider})
      {:ok, provider}
    end
  end

  def change_provider(%Scope{} = scope, %Provider{} = provider, attrs \\ %{}) do
    true = provider.user_id == scope.user.id

    Provider.changeset(provider, attrs, scope)
  end

  def subscribe_provider_types(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ServiceHub.PubSub, "user:#{key}:provider_types")
  end

  defp broadcast_provider_type(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ServiceHub.PubSub, "user:#{key}:provider_types", message)
  end

  def list_provider_types(%Scope{} = scope) do
    ProviderType
    |> where(user_id: ^scope.user.id)
    |> order_by([pt], asc: pt.name)
    |> Repo.all()
  end

  def get_provider_type!(%Scope{} = scope, id) do
    ProviderType
    |> where(id: ^id, user_id: ^scope.user.id)
    |> Repo.one!()
  end

  def create_provider_type(%Scope{} = scope, attrs) do
    with {:ok, provider_type = %ProviderType{}} <-
           %ProviderType{}
           |> ProviderType.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_provider_type(scope, {:created, provider_type})
      {:ok, provider_type}
    end
  end

  @doc """
  Updates a provider_type.

  ## Examples

      iex> update_provider_type(scope, provider_type, %{field: new_value})
      {:ok, %ProviderType{}}

      iex> update_provider_type(scope, provider_type, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_provider_type(%Scope{} = scope, %ProviderType{} = provider_type, attrs) do
    true = provider_type.user_id == scope.user.id

    with {:ok, provider_type = %ProviderType{}} <-
           provider_type
           |> ProviderType.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_provider_type(scope, {:updated, provider_type})
      {:ok, provider_type}
    end
  end

  def delete_provider_type(%Scope{} = scope, %ProviderType{} = provider_type) do
    true = provider_type.user_id == scope.user.id

    with {:ok, provider_type = %ProviderType{}} <-
           Repo.delete(provider_type) do
      broadcast_provider_type(scope, {:deleted, provider_type})
      {:ok, provider_type}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking provider_type changes.

  ## Examples

      iex> change_provider_type(scope, provider_type)
      %Ecto.Changeset{data: %ProviderType{}}

  """
  def change_provider_type(%Scope{} = scope, %ProviderType{} = provider_type, attrs \\ %{}) do
    true = provider_type.user_id == scope.user.id

    ProviderType.changeset(provider_type, attrs, scope)
  end

  def subscribe_auth_types(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ServiceHub.PubSub, "user:#{key}:auth_types")
  end

  defp broadcast_auth_type(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ServiceHub.PubSub, "user:#{key}:auth_types", message)
  end

  def list_auth_types(%Scope{} = scope) do
    AuthType
    |> where(user_id: ^scope.user.id)
    |> order_by([at], asc: at.name)
    |> Repo.all()
  end

  def get_auth_type!(%Scope{} = scope, id) do
    AuthType
    |> where(id: ^id, user_id: ^scope.user.id)
    |> Repo.one!()
  end

  def create_auth_type(%Scope{} = scope, attrs) do
    with {:ok, auth_type = %AuthType{}} <-
           %AuthType{}
           |> AuthType.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_auth_type(scope, {:created, auth_type})
      {:ok, auth_type}
    end
  end

  @doc """
  Updates a auth_type.

  ## Examples

      iex> update_auth_type(scope, auth_type, %{field: new_value})
      {:ok, %AuthType{}}

      iex> update_auth_type(scope, auth_type, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_auth_type(%Scope{} = scope, %AuthType{} = auth_type, attrs) do
    true = auth_type.user_id == scope.user.id

    with {:ok, auth_type = %AuthType{}} <-
           auth_type
           |> AuthType.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_auth_type(scope, {:updated, auth_type})
      {:ok, auth_type}
    end
  end

  def delete_auth_type(%Scope{} = scope, %AuthType{} = auth_type) do
    true = auth_type.user_id == scope.user.id

    with {:ok, auth_type = %AuthType{}} <-
           Repo.delete(auth_type) do
      broadcast_auth_type(scope, {:deleted, auth_type})
      {:ok, auth_type}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking auth_type changes.

  ## Examples

      iex> change_auth_type(scope, auth_type)
      %Ecto.Changeset{data: %AuthType{}}

  """
  def change_auth_type(%Scope{} = scope, %AuthType{} = auth_type, attrs \\ %{}) do
    true = auth_type.user_id == scope.user.id

    AuthType.changeset(auth_type, attrs, scope)
  end
end
