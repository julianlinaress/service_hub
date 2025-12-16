defmodule ServiceHub.Providers do
  import Ecto.Query, warn: false
  alias ServiceHub.Repo

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.ProviderAdapters
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

  def get_provider!(%Scope{} = scope, %Provider{} = provider) do
    true = provider.user_id == scope.user.id

    Repo.preload(provider, [:provider_type, :auth_type])
  end

  def get_provider!(%Scope{} = scope, id) do
    Provider
    |> where(id: ^parse_id(id), user_id: ^scope.user.id)
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
    # Allow fresh structs without user_id while still enforcing ownership on persisted records
    true = is_nil(provider.user_id) || provider.user_id == scope.user.id

    Provider.changeset(provider, attrs, scope)
  end

  def validate_provider_connection(%Scope{} = scope, provider_or_id) do
    provider = get_provider!(scope, provider_or_id)
    now = DateTime.utc_now(:second)

    status_update =
      case ProviderAdapters.validate_connection(provider) do
        :ok ->
          %{
            last_validation_status: "ok",
            last_validation_error: nil,
            last_validated_at: now
          }

        {:error, reason} ->
          %{
            last_validation_status: "error",
            last_validation_error: format_validation_error(reason),
            last_validated_at: now
          }
      end

    with {:ok, provider} <-
           provider
           |> Ecto.Changeset.change(status_update)
           |> Repo.update() do
      broadcast_provider(scope, {:updated, provider})
      {:ok, provider}
    end
  end

  def create_provider_token(
        %Scope{} = scope,
        provider_or_id,
        %{
          "username" => username,
          "password" => password
        } = params
      ) do
    provider = get_provider!(scope, provider_or_id)

    with {:ok, token} <- ProviderAdapters.create_token(provider, username, password, params),
         {:ok, provider} <-
           provider
           |> Ecto.Changeset.change(auth_data: Map.put(provider.auth_data || %{}, "token", token))
           |> Repo.update() do
      broadcast_provider(scope, {:updated, provider})
      {:ok, token}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def apply_account_connection(%Scope{} = scope, %Provider{} = provider, conn_attrs) do
    true = provider.user_id == scope.user.id

    auth_data =
      provider.auth_data
      |> Kernel.||(%{})
      |> Map.merge(conn_attrs)

    provider
    |> Ecto.Changeset.change(auth_data: auth_data)
    |> Repo.update()
  end

  def save_provider_auth_data(%Scope{} = scope, %Provider{} = provider, attrs)
      when is_map(attrs) do
    true = provider.user_id == scope.user.id

    merged =
      provider.auth_data
      |> Kernel.||(%{})
      |> Map.merge(attrs)

    with {:ok, provider} <-
           provider
           |> Ecto.Changeset.change(auth_data: merged)
           |> Repo.update() do
      broadcast_provider(scope, {:updated, provider})
      {:ok, provider}
    end
  end

  defp format_validation_error(:unauthorized), do: "Unauthorized"
  defp format_validation_error(:not_found), do: "Provider not reachable"
  defp format_validation_error(:forbidden), do: "Forbidden"
  defp format_validation_error(:missing_token), do: "Missing token in auth data"
  defp format_validation_error(:bad_request), do: "Bad request to provider"
  defp format_validation_error(:missing_auth_type), do: "No auth type configured"

  defp format_validation_error({:missing_auth_field, field}),
    do: "Missing auth field #{field}"

  defp format_validation_error({:unexpected_status, status}),
    do: "Unexpected response (#{status})"

  defp format_validation_error({:unexpected_status, status, _body}),
    do: "Unexpected response (#{status})"

  defp format_validation_error(:invalid_private_key), do: "Invalid private key"
  defp format_validation_error(:invalid_jwt_payload), do: "Invalid JWT payload"
  defp format_validation_error(:invalid_base_url), do: "Invalid base URL"
  defp format_validation_error(:unsupported_auth_type), do: "Unsupported auth type"

  defp format_validation_error(reason), do: inspect(reason)

  def subscribe_provider_types(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ServiceHub.PubSub, "user:#{key}:provider_types")
  end

  defp broadcast_provider_type(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ServiceHub.PubSub, "user:#{key}:provider_types", message)
  end

  def list_provider_types(%Scope{} = _scope) do
    ProviderType
    |> order_by([pt], asc: pt.name)
    |> Repo.all()
  end

  def get_provider_type!(%Scope{} = _scope, id) do
    ProviderType
    |> where(id: ^id)
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
    with {:ok, provider_type = %ProviderType{}} <-
           provider_type
           |> ProviderType.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_provider_type(scope, {:updated, provider_type})
      {:ok, provider_type}
    end
  end

  def delete_provider_type(%Scope{} = scope, %ProviderType{} = provider_type) do
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

  def list_auth_types(%Scope{} = _scope) do
    AuthType
    |> order_by([at], asc: at.name)
    |> Repo.all()
  end

  def get_auth_type!(%Scope{} = _scope, id) do
    AuthType
    |> where(id: ^id)
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
    with {:ok, auth_type = %AuthType{}} <-
           auth_type
           |> AuthType.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_auth_type(scope, {:updated, auth_type})
      {:ok, auth_type}
    end
  end

  def delete_auth_type(%Scope{} = scope, %AuthType{} = auth_type) do
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
    AuthType.changeset(auth_type, attrs, scope)
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, _} -> parsed
      :error -> id
    end
  end

  defp parse_id(id), do: id
end
