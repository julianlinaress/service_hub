defmodule ServiceHub.ProviderAdapters.Behaviour do
  @moduledoc """
  Behaviour for provider adapters.
  """

  alias ServiceHub.Providers.Provider

  @callback validate_connection(%Provider{}) ::
              :ok | {:error, :unauthorized | :not_found | term()}

  @callback fetch_repo_metadata(%Provider{}, owner :: String.t(), repo :: String.t()) ::
              {:ok, map()} | {:error, :unauthorized | :not_found | term()}

  @callback list_repositories(%Provider{}) ::
              {:ok, list(map())}
              | {:error, :unauthorized | :not_found | :unsupported_auth_type | term()}

  @callback list_branches(%Provider{}, owner :: String.t(), repo :: String.t()) ::
              {:ok, list(map())}
              | {:error, :unauthorized | :not_found | :unsupported_auth_type | term()}

  @callback dispatch_workflow(%Provider{}, map()) :: {:ok, map()} | {:error, term()}

  @callback create_token(
              %Provider{},
              username :: String.t(),
              password :: String.t(),
              attrs :: map()
            ) ::
              {:ok, token :: String.t()} | {:error, term()}

  @callback authorize_url(%Provider{}, redirect_uri :: String.t(), state :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback exchange_oauth_token(%Provider{}, code :: String.t(), redirect_uri :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback default_oauth_scope() :: String.t() | nil
end
