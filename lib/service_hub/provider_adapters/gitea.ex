defmodule ServiceHub.ProviderAdapters.Gitea do
  @moduledoc """
  Gitea provider adapter. Uses token-based authentication for admin requests.
  """

  @behaviour ServiceHub.ProviderAdapters.Behaviour

  alias ServiceHub.Providers.Provider

  def validate_connection(%Provider{} = provider) do
    case get(provider, "/api/v1/user") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_repo_metadata(%Provider{} = provider, owner, repo) do
    path = "/api/v1/repos/#{owner}/#{repo}"

    case get(provider, path) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def dispatch_workflow(_provider, _attrs) do
    {:error, :not_implemented}
  end

  def create_token(%Provider{} = provider, username, password, attrs) do
    token_name = Map.get(attrs, "name") || Map.get(attrs, :name) || "service_hub_token"
    scopes = normalize_scopes(attrs)
    payload = %{"name" => token_name, "scopes" => scopes}

    with {:ok, url} <- build_url(provider.base_url, "/api/v1/users/#{username}/tokens"),
         {:ok, response} <-
           Req.request(
             method: :post,
             url: url,
             auth: {:basic, "#{username}:#{password}"},
             json: payload
           ) do
      case response do
        %{status: status, body: %{"sha1" => token}} when status in 200..299 ->
          {:ok, token}

        %{status: 401} ->
          {:error, :unauthorized}

        %{status: status, body: body} ->
          {:error, {:unexpected_status, status, body}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get(provider, path) do
    with {:ok, url} <- build_url(provider.base_url, path),
         {:ok, token} <- fetch_token(provider),
         {:ok, response} <-
           Req.request(method: :get, url: url, headers: [{"authorization", "token #{token}"}]) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_url(base, path) do
    case URI.parse(base) do
      %URI{scheme: nil} -> {:error, :invalid_base_url}
      %URI{} = uri -> {:ok, URI.merge(uri, path) |> URI.to_string()}
    end
  rescue
    _ -> {:error, :invalid_base_url}
  end

  defp fetch_token(%Provider{auth_data: auth_data}) do
    token = Map.get(auth_data, "token") || Map.get(auth_data, :token)

    if token do
      {:ok, token}
    else
      {:error, :missing_token}
    end
  end

  defp normalize_scopes(attrs) do
    scopes =
      case Map.get(attrs, "scopes") || Map.get(attrs, :scopes) do
        list when is_list(list) -> Enum.map(list, &to_string/1)
        scopes when is_binary(scopes) -> scopes |> String.split(",") |> Enum.map(&String.trim/1)
        _ -> []
      end

    scopes = Enum.reject(scopes, &(&1 == ""))

    if scopes == [] do
      default_scopes()
    else
      scopes
    end
  end

  defp default_scopes do
    [
      "read:repository",
      "write:repository",
      "read:user",
      "read:notification"
    ]
  end
end
