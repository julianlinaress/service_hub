defmodule ServiceHub.Services do
  import Ecto.Query, warn: false
  alias ServiceHub.Repo

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.ProviderAdapters
  alias ServiceHub.Providers.Provider
  alias ServiceHub.Services.Service

  def subscribe_services(%Scope{} = scope, provider_id) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ServiceHub.PubSub, "user:#{key}:provider:#{provider_id}:services")
  end

  defp broadcast_service(%Scope{} = scope, provider_id, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(
      ServiceHub.PubSub,
      "user:#{key}:provider:#{provider_id}:services",
      message
    )
  end

  def list_services_for_provider(%Scope{} = scope, %Provider{id: provider_id}) do
    Service
    |> join(:inner, [s], p in assoc(s, :provider))
    |> where([s, p], s.provider_id == ^provider_id and p.user_id == ^scope.user.id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  def list_services(%Scope{} = scope) do
    Service
    |> join(:inner, [s], p in assoc(s, :provider))
    |> where([s, p], p.user_id == ^scope.user.id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  def count_services_for_provider(%Scope{} = scope, provider_id) do
    Service
    |> join(:inner, [s], p in assoc(s, :provider))
    |> where([s, p], s.provider_id == ^provider_id and p.user_id == ^scope.user.id)
    |> select([s], count(s.id))
    |> Repo.one() || 0
  end

  def get_service!(%Scope{} = scope, id) do
    Service
    |> join(:inner, [s], p in assoc(s, :provider))
    |> where([s, p], s.id == ^id and p.user_id == ^scope.user.id)
    |> preload([:provider])
    |> Repo.one!()
  end

  def create_service(%Scope{} = scope, attrs) do
    with {:ok, provider} <- fetch_provider(scope, provider_id_from_attrs(attrs)),
         changeset <- Service.changeset(%Service{provider_id: provider.id}, attrs),
         {:ok, _} <- ensure_provider_validated(provider, changeset),
         {:ok, _} <- validate_repo(provider, changeset),
         {:ok, service} <- Repo.insert(changeset) do
      broadcast_service(scope, provider.id, {:created, service})
      {:ok, service}
    end
  end

  def update_service(%Scope{} = scope, %Service{} = service, attrs) do
    service = Repo.preload(service, provider: [:provider_type, :auth_type])
    true = service.provider.user_id == scope.user.id

    changeset = Service.changeset(service, attrs)

    with {:ok, _} <- ensure_provider_validated(service.provider, changeset),
         {:ok, _} <- validate_repo(service.provider, changeset),
         {:ok, service} <- Repo.update(changeset) do
      broadcast_service(scope, service.provider_id, {:updated, service})
      {:ok, service}
    end
  end

  def delete_service(%Scope{} = scope, %Service{} = service) do
    service = Repo.preload(service, :provider)
    true = service.provider.user_id == scope.user.id

    with {:ok, service} <- Repo.delete(service) do
      broadcast_service(scope, service.provider_id, {:deleted, service})
      {:ok, service}
    end
  end

  def change_service(%Scope{} = scope, %Service{} = service, attrs \\ %{}) do
    service = Repo.preload(service, :provider)

    case service.provider do
      %Provider{user_id: user_id} when user_id == scope.user.id ->
        Service.changeset(service, attrs)

      _ ->
        service
        |> Service.changeset(attrs)
        |> Ecto.Changeset.add_error(:provider_id, "is invalid for this user")
    end
  end

  defp validate_repo(provider, %Ecto.Changeset{} = changeset) do
    if changeset.valid? do
      owner = Ecto.Changeset.get_field(changeset, :owner)
      repo = Ecto.Changeset.get_field(changeset, :repo)

      case ProviderAdapters.fetch_repo_metadata(provider, owner, repo) do
        {:ok, _} -> {:ok, provider}
        {:error, reason} -> {:error, add_repo_error(changeset, reason)}
      end
    else
      {:ok, provider}
    end
  end

  defp add_repo_error(changeset, :unauthorized) do
    Ecto.Changeset.add_error(
      changeset,
      :repo,
      "Cannot access repository with current provider credentials"
    )
  end

  defp add_repo_error(changeset, :not_found) do
    Ecto.Changeset.add_error(changeset, :repo, "Repository not found in provider")
  end

  defp add_repo_error(changeset, {:unexpected_status, status}) do
    Ecto.Changeset.add_error(changeset, :repo, "Unexpected response (status #{status})")
  end

  defp add_repo_error(changeset, reason) do
    Ecto.Changeset.add_error(changeset, :repo, "Unable to verify repository: #{inspect(reason)}")
  end

  defp ensure_provider_validated(%Provider{} = provider, %Ecto.Changeset{} = changeset) do
    if provider_validated?(provider) do
      {:ok, provider}
    else
      {:error,
       Ecto.Changeset.add_error(
         changeset,
         :provider_id,
         "Validate the provider connection before managing services"
       )}
    end
  end

  defp provider_validated?(%Provider{last_validation_status: status}) do
    status == "ok"
  end

  defp fetch_provider(%Scope{} = scope, provider_id) when is_integer(provider_id) do
    provider =
      Provider
      |> where(user_id: ^scope.user.id, id: ^provider_id)
      |> preload([:provider_type, :auth_type])
      |> Repo.one()

    case provider do
      %Provider{} = provider -> {:ok, provider}
      _ -> {:error, :provider_not_found}
    end
  end

  defp fetch_provider(_, _), do: {:error, :provider_not_found}

  defp provider_id_from_attrs(%{"provider_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp provider_id_from_attrs(%{"provider_id" => id}) when is_integer(id), do: id
  defp provider_id_from_attrs(%{provider_id: id}) when is_integer(id), do: id
  defp provider_id_from_attrs(_), do: nil
end
