defmodule ServiceHub.ServiceClients do
  @moduledoc """
  Context for managing ServiceClients (installations).
  """

  import Ecto.Query, warn: false
  alias ServiceHub.Repo
  alias ServiceHub.Accounts.Scope
  alias ServiceHub.ServiceClients.ServiceClient

  @doc """
  Lists all service clients for a given set of service IDs.
  Returns service_clients with preloaded client associations.
  """
  def list_service_clients_for_services(%Scope{} = scope, service_ids)
      when is_list(service_ids) do
    from(sc in ServiceClient,
      join: s in assoc(sc, :service),
      join: p in assoc(s, :provider),
      where: p.user_id == ^scope.user.id,
      where: sc.service_id in ^service_ids,
      preload: [:client, service: :provider]
    )
    |> Repo.all()
  end

  @doc """
  Lists all service clients for a specific service.
  """
  def list_service_clients_for_service(%Scope{} = scope, service_id) do
    list_service_clients_for_services(scope, [service_id])
  end
end
