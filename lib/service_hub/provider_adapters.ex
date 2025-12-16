defmodule ServiceHub.ProviderAdapters do
  @moduledoc """
  Adapter dispatcher for provider integrations.
  """

  alias ServiceHub.ProviderAdapters.GitHub
  alias ServiceHub.ProviderAdapters.Gitea
  alias ServiceHub.Providers.{Provider, ProviderType}

  @adapters %{
    "gitea" => Gitea,
    "github" => GitHub
  }

  def validate_connection(%Provider{} = provider) do
    with {:ok, adapter} <- adapter_for(provider) do
      adapter.validate_connection(provider)
    end
  end

  def fetch_repo_metadata(%Provider{} = provider, owner, repo) do
    with {:ok, adapter} <- adapter_for(provider) do
      adapter.fetch_repo_metadata(provider, owner, repo)
    end
  end

  def create_token(%Provider{} = provider, username, password, attrs) do
    with {:ok, adapter} <- adapter_for(provider) do
      adapter.create_token(provider, username, password, attrs)
    end
  end

  def authorize_url(%Provider{} = provider, redirect_uri, state) do
    with {:ok, adapter} <- adapter_for(provider) do
      adapter.authorize_url(provider, redirect_uri, state)
    end
  end

  def exchange_oauth_token(%Provider{} = provider, code, redirect_uri) do
    with {:ok, adapter} <- adapter_for(provider) do
      adapter.exchange_oauth_token(provider, code, redirect_uri)
    end
  end

  def adapter_for_key!(key) do
    case Map.fetch(@adapters, key) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "Unsupported provider key #{inspect(key)}"
    end
  end

  defp adapter_for(%Provider{provider_type: %ProviderType{key: key}}) do
    case Map.fetch(@adapters, key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_provider_type}
    end
  end

  defp adapter_for(%Provider{provider_type: %{key: key}}) do
    case Map.fetch(@adapters, key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_provider_type}
    end
  end

  defp adapter_for(_), do: {:error, :unsupported_provider_type}
end
