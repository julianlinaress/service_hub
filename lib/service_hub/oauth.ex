defmodule ServiceHub.OAuth do
  @moduledoc """
  Centralized OAuth config and helpers for user-level connections.
  """

  alias ServiceHub.ProviderAdapters
  alias ServiceHub.Providers.Provider

  @default_base "https://api.github.com"

  def github_provider(attrs \\ %{}) do
    base_url = Map.get(attrs, :base_url) || Map.get(attrs, "base_url") || default_base_url()
    client_id = Map.get(attrs, :client_id) || Map.get(attrs, "client_id") || client_id!()

    client_secret =
      Map.get(attrs, :client_secret) || Map.get(attrs, "client_secret") || client_secret!()

    scope =
      Map.get(attrs, :scope) || Map.get(attrs, "scope") ||
        ProviderAdapters.adapter_for_key!("github").default_oauth_scope()

    %Provider{
      base_url: base_url,
      provider_type: %{key: "github"},
      auth_type: %{key: "github_oauth"},
      auth_data: %{
        "client_id" => client_id,
        "client_secret" => client_secret,
        "scope" => scope
      }
    }
  end

  defp default_base_url do
    Application.get_env(:service_hub, :github_oauth_base_url, @default_base)
  end

  defp client_id! do
    Application.fetch_env!(:service_hub, :github_oauth_client_id)
  end

  defp client_secret! do
    Application.fetch_env!(:service_hub, :github_oauth_client_secret)
  end
end
