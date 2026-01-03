defmodule ServiceHub.Deployments do
  @moduledoc """
  Deployment management for services. Health checks are mandatory (with per-deployment
  expectations); version checks are optional and can be toggled per deployment.
  """
  import Ecto.Query, warn: false

  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Repo
  alias ServiceHub.Services.Service

  def list_deployments_for_service(%Scope{} = scope, service_id) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :service))
    |> join(:inner, [_d, s], p in assoc(s, :provider))
    |> where([_d, s, p], s.id == ^service_id and p.user_id == ^scope.user.id)
    |> preload([d, _s, _p], service: :provider)
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  def get_deployment!(%Scope{} = scope, id) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :service))
    |> join(:inner, [_d, s], p in assoc(s, :provider))
    |> where([d, _s, p], d.id == ^id and p.user_id == ^scope.user.id)
    |> preload([d, _s, _p], service: :provider)
    |> Repo.one!()
  end

  def create_deployment(%Scope{} = scope, attrs) do
    with {:ok, service} <- fetch_service(scope, service_id_from_attrs(attrs)),
         changeset <- Deployment.changeset(%Deployment{service_id: service.id}, attrs),
         {:ok, deployment} <- Repo.insert(changeset) do
      {:ok, Repo.preload(deployment, service: :provider)}
    end
  end

  def update_deployment(%Scope{} = scope, %Deployment{} = deployment, attrs) do
    deployment = preload_service(deployment)
    true = deployment.service.provider.user_id == scope.user.id

    deployment
    |> Deployment.changeset(attrs)
    |> Repo.update()
  end

  def delete_deployment(%Scope{} = scope, %Deployment{} = deployment) do
    deployment = preload_service(deployment)
    true = deployment.service.provider.user_id == scope.user.id

    Repo.delete(deployment)
  end

  def change_deployment(%Scope{} = scope, %Deployment{} = deployment, attrs \\ %{}) do
    deployment = preload_service(deployment)

    case deployment.service.provider do
      %{user_id: user_id} when user_id == scope.user.id ->
        Deployment.changeset(deployment, attrs)

      _ ->
        deployment
        |> Deployment.changeset(attrs)
        |> Ecto.Changeset.add_error(:service_id, "is invalid for this user")
    end
  end

  defp fetch_service(%Scope{} = scope, service_id) when is_integer(service_id) do
    service =
      Service
      |> join(:inner, [s], p in assoc(s, :provider))
      |> where([s, p], s.id == ^service_id and p.user_id == ^scope.user.id)
      |> preload([_s, p], :provider)
      |> Repo.one()

    case service do
      %Service{} = service -> {:ok, service}
      _ -> {:error, :service_not_found}
    end
  end

  defp fetch_service(_, _), do: {:error, :service_not_found}

  defp preload_service(%Deployment{} = deployment) do
    Repo.preload(deployment, service: :provider)
  end

  defp service_id_from_attrs(%{"service_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp service_id_from_attrs(%{"service_id" => id}) when is_integer(id), do: id
  defp service_id_from_attrs(%{service_id: id}) when is_integer(id), do: id
  defp service_id_from_attrs(_), do: nil
end
