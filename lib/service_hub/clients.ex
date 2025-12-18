defmodule ServiceHub.Clients do
  @moduledoc """
  Context for managing Clients.
  """

  import Ecto.Query, warn: false
  alias ServiceHub.Repo
  alias ServiceHub.Accounts.Scope
  alias ServiceHub.Clients.Client

  @doc """
  Gets a single client.
  """
  def get_client!(%Scope{} = _scope, id) do
    Repo.get!(Client, id)
  end

  @doc """
  Lists all clients.
  """
  def list_clients(%Scope{} = _scope) do
    Repo.all(Client)
  end
end
