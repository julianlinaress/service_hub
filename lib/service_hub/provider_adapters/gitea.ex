defmodule ServiceHub.ProviderAdapters.Gitea do
  @moduledoc """
  Gitea provider adapter. Uses token-based authentication for admin requests.
  """

  @behaviour ServiceHub.ProviderAdapters.Behaviour

  alias ServiceHub.Providers.Provider

  @impl true
  def validate_connection(%Provider{} = provider) do
    log("Validating connection to #{provider.base_url}")

    result =
      case get(provider, "/api/v1/user") do
        {:ok, %{status: 200}} ->
          log("Connection successful (200)")
          :ok

        {:ok, %{status: 401}} ->
          log("Connection failed: unauthorized (401)")
          {:error, :unauthorized}

        {:ok, %{status: 404}} ->
          log("Connection failed: not found (404)")
          {:error, :not_found}

        {:ok, %{status: status}} ->
          log("Connection failed: unexpected status #{status}")
          {:error, {:unexpected_status, status}}

        {:error, reason} ->
          log("Connection failed: #{inspect(reason)}")
          {:error, reason}
      end

    log("validate_connection returning: #{inspect(result)}")
    result
  end

  @impl true
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

  @impl true
  def dispatch_workflow(_provider, _attrs) do
    {:error, :not_implemented}
  end

  @impl true
  def list_repositories(%Provider{} = provider) do
    paginate_repositories(provider, 1, [])
  end

  @impl true
  def list_branches(%Provider{} = provider, owner, repo) do
    paginate_branches(provider, owner, repo, 1, [])
  end

  defp paginate_repositories(provider, page, acc) do
    params = %{limit: 100, page: page}

    case get(provider, "/api/v1/user/repos", params: params) do
      {:ok, %{status: 200, body: repos}} when is_list(repos) ->
        merged = acc ++ filter_admin_repositories(repos)

        if length(repos) < params.limit do
          {:ok, format_repositories(merged)}
        else
          paginate_repositories(provider, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_admin_repositories(repos) do
    Enum.filter(repos, fn repo ->
      permissions =
        Map.get(repo, "permissions") ||
          Map.get(repo, :permissions) ||
          %{}

      admin? = Map.get(permissions, "admin") == true || Map.get(permissions, :admin) == true
      push? = Map.get(permissions, "push") == true || Map.get(permissions, :push) == true

      admin? or push?
    end)
  end

  defp format_repositories(repos) do
    Enum.map(repos, fn repo ->
      owner_map =
        Map.get(repo, "owner") ||
          Map.get(repo, :owner) ||
          %{}

      owner = Map.get(owner_map, "login") || Map.get(owner_map, :login)

      name = Map.get(repo, "name") || Map.get(repo, :name)

      %{
        id: Map.get(repo, "id") || Map.get(repo, :id),
        owner: owner,
        name: name,
        full_name:
          Map.get(repo, "full_name") ||
            Map.get(repo, :full_name) ||
            build_full_name(owner, name),
        private: Map.get(repo, "private", false) || Map.get(repo, :private, false)
      }
    end)
  end

  defp build_full_name(owner, name) when is_binary(owner) and is_binary(name) do
    "#{owner}/#{name}"
  end

  defp build_full_name(_, name), do: name

  defp paginate_branches(provider, owner, repo, page, acc) do
    params = %{limit: 100, page: page}

    case get(provider, "/api/v1/repos/#{owner}/#{repo}/branches", params: params) do
      {:ok, %{status: 200, body: branches}} when is_list(branches) ->
        merged = acc ++ format_branches(branches)

        if length(branches) < params.limit do
          {:ok, merged}
        else
          paginate_branches(provider, owner, repo, page + 1, merged)
        end

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_branches(branches) do
    Enum.map(branches, fn branch ->
      %{
        name: Map.get(branch, "name") || Map.get(branch, :name),
        protected:
          Map.get(branch, "protected", false) ||
            Map.get(branch, :protected, false),
        commit_sha:
          branch
          |> Map.get("commit")
          |> case do
            %{"id" => sha} -> sha
            %{id: sha} -> sha
            _ -> nil
          end
      }
    end)
  end

  @impl true
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

  defp get(provider, path, opts \\ []) do
    with {:ok, url} <- build_url(provider.base_url, path),
         {:ok, token} <- fetch_token(provider) do
      case Req.request(
             Keyword.merge(
               [method: :get, url: url, headers: [{"authorization", "token #{token}"}]],
               opts
             )
           ) do
        {:ok, response} -> {:ok, response}
        {:error, %Mint.TransportError{reason: :econnrefused}} -> {:error, :connection_refused}
        {:error, %Mint.TransportError{reason: :nxdomain}} -> {:error, :dns_error}
        {:error, exception} -> {:error, {:request_failed, Exception.message(exception)}}
      end
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

  @impl true
  def authorize_url(_provider, _redirect_uri, _state), do: {:error, :not_supported}

  @impl true
  def exchange_oauth_token(_provider, _code, _redirect_uri), do: {:error, :not_supported}

  @impl true
  def default_oauth_scope, do: nil

  defp log(message) do
    require Logger
    Logger.info("[Gitea] #{message}", ansi_color: :magenta)
  end
end
