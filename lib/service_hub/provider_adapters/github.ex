defmodule ServiceHub.ProviderAdapters.GitHub do
  @moduledoc """
  GitHub provider adapter. Supports PATs and GitHub App installations.
  """

  @behaviour ServiceHub.ProviderAdapters.Behaviour

  alias ServiceHub.Providers.Provider

  @api_version "2022-11-28"

  @impl true
  def validate_connection(%Provider{} = provider) do
    case auth_mode(provider) do
      :installation ->
        case request(provider, :get, "/installation/repositories", params: %{per_page: 1}) do
          {:ok, %{status: 200}} -> :ok
          {:ok, %{status: 401}} -> {:error, :unauthorized}
          {:ok, %{status: 403}} -> {:error, :forbidden}
          {:ok, %{status: 404}} -> {:error, :not_found}
          {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        case request(provider, :get, "/user") do
          {:ok, %{status: 200}} -> :ok
          {:ok, %{status: 401}} -> {:error, :unauthorized}
          {:ok, %{status: 404}} -> {:error, :not_found}
          {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def fetch_repo_metadata(%Provider{} = provider, owner, repo) do
    case request(provider, :get, "/repos/#{owner}/#{repo}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 403}} -> {:error, :forbidden}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_repositories(%Provider{} = provider) do
    case auth_mode(provider) do
      :installation -> list_installation_repositories(provider)
      :oauth -> list_user_repositories(provider)
      :pat -> list_user_repositories(provider)
      :unknown -> {:error, :unsupported_auth_type}
    end
  end

  @impl true
  def list_branches(%Provider{} = provider, owner, repo) do
    paginate_branches(provider, owner, repo, 1, [])
  end

  defp list_installation_repositories(%Provider{} = provider) do
    paginate_installation_repositories(provider, 1, [])
  end

  defp paginate_installation_repositories(provider, page, acc) do
    params = %{per_page: 100, page: page}

    case request(provider, :get, "/installation/repositories", params: params) do
      {:ok, %{status: 200, body: %{"repositories" => repos}}} ->
        formatted = format_repositories(repos || [])
        merged = acc ++ formatted

        if length(repos || []) < params.per_page do
          {:ok, merged}
        else
          paginate_installation_repositories(provider, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_user_repositories(%Provider{} = provider) do
    user_repos = paginate_user_repositories(provider, 1, [])
    org_repos = list_org_admin_repositories(provider)

    with {:ok, user_repos} <- user_repos,
         {:ok, org_repos} <- org_repos do
      {:ok, uniq_repositories(user_repos ++ org_repos)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp paginate_user_repositories(provider, page, acc) do
    params = %{
      per_page: 100,
      page: page,
      affiliation: "owner,collaborator,organization_member",
      visibility: "all"
    }

    case request(provider, :get, "/user/repos", params: params) do
      {:ok, %{status: 200, body: repos}} when is_list(repos) ->
        merged = acc ++ filter_admin_repositories(repos)

        if length(repos) < params.per_page do
          {:ok, format_repositories(merged)}
        else
          paginate_user_repositories(provider, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_org_admin_repositories(provider) do
    case paginate_org_memberships(provider, 1, []) do
      {:ok, orgs} ->
        orgs
        |> Enum.flat_map(&org_repositories(provider, &1))
        |> uniq_repositories()
        |> wrap_ok()

      {:error, :forbidden} ->
        case paginate_user_orgs(provider, 1, []) do
          {:ok, orgs} ->
            orgs
            |> Enum.flat_map(&org_repositories(provider, &1))
            |> uniq_repositories()
            |> wrap_ok()

          {:error, :unauthorized} ->
            {:error, :unauthorized}

          {:error, reason} ->
            {:ok, []} |> maybe_error(reason)
        end

      {:error, :unauthorized} ->
        {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp paginate_org_memberships(provider, page, acc) do
    params = %{per_page: 100, page: page, state: "active"}

    case request(provider, :get, "/user/memberships/orgs", params: params) do
      {:ok, %{status: 200, body: orgs}} when is_list(orgs) ->
        admin_orgs =
          Enum.filter(orgs, fn org ->
            role = Map.get(org, "role") || Map.get(org, :role)
            state = Map.get(org, "state") || Map.get(org, :state)
            role in ["admin", :admin] and state in ["active", :active]
          end)

        merged = acc ++ Enum.map(admin_orgs, &normalize_org/1)

        if length(orgs) < params.per_page do
          {:ok, merged}
        else
          paginate_org_memberships(provider, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp paginate_user_orgs(provider, page, acc) do
    params = %{per_page: 100, page: page}

    case request(provider, :get, "/user/orgs", params: params) do
      {:ok, %{status: 200, body: orgs}} when is_list(orgs) ->
        merged = acc ++ Enum.map(orgs, &normalize_org/1)

        if length(orgs) < params.per_page do
          {:ok, merged}
        else
          paginate_user_orgs(provider, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_org(org) do
    org_map =
      Map.get(org, "organization") ||
        Map.get(org, :organization) ||
        org

    %{
      login: Map.get(org_map, "login") || Map.get(org_map, :login)
    }
  end

  defp org_repositories(_provider, %{login: nil}), do: []

  defp org_repositories(provider, %{login: login}) do
    case paginate_org_repositories(provider, login, 1, []) do
      {:ok, repos} -> repos
      {:error, _} -> []
    end
  end

  defp paginate_org_repositories(provider, org, page, acc) do
    params = %{per_page: 100, page: page, type: "all"}

    case request(provider, :get, "/orgs/#{org}/repos", params: params) do
      {:ok, %{status: 200, body: repos}} when is_list(repos) ->
        merged = acc ++ filter_admin_repositories(repos)

        if length(repos) < params.per_page do
          {:ok, format_repositories(merged)}
        else
          paginate_org_repositories(provider, org, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp uniq_repositories(repos) do
    repos
    |> Enum.reduce(%{}, fn repo, acc ->
      key = repo[:id] || repo[:full_name] || repo[:name]
      Map.put_new(acc, key, repo)
    end)
    |> Map.values()
  end

  defp wrap_ok(value), do: {:ok, value}

  defp maybe_error({:ok, value}, reason) do
    case reason do
      :unauthorized -> {:error, :unauthorized}
      _ -> {:ok, value}
    end
  end

  defp filter_admin_repositories(repos) do
    Enum.filter(repos, fn repo ->
      permissions =
        Map.get(repo, "permissions") ||
          Map.get(repo, :permissions) ||
          %{}

      admin? = Map.get(permissions, "admin") == true || Map.get(permissions, :admin) == true

      maintain? =
        Map.get(permissions, "maintain") == true || Map.get(permissions, :maintain) == true

      push? = Map.get(permissions, "push") == true || Map.get(permissions, :push) == true

      admin? or maintain? or push? or map_size(permissions) == 0
    end)
  end

  defp format_repositories(repos) do
    Enum.map(repos, &format_repository/1)
  end

  defp format_repository(repo) do
    owner_map =
      Map.get(repo, "owner") ||
        Map.get(repo, :owner) ||
        %{}

    owner = Map.get(owner_map, "login") || Map.get(owner_map, :login)

    name = Map.get(repo, "name") || Map.get(repo, :name)

    full_name =
      Map.get(repo, "full_name") || Map.get(repo, :full_name) || build_full_name(owner, name)

    private? = Map.get(repo, "private", false) || Map.get(repo, :private, false)

    %{
      id: Map.get(repo, "id") || Map.get(repo, :id),
      owner: owner,
      name: name,
      full_name: full_name,
      private: private?
    }
  end

  defp build_full_name(owner, name) when is_binary(owner) and is_binary(name) do
    "#{owner}/#{name}"
  end

  defp build_full_name(_, name), do: name

  defp paginate_branches(provider, owner, repo, page, acc) do
    params = %{per_page: 100, page: page}

    case request(provider, :get, "/repos/#{owner}/#{repo}/branches", params: params) do
      {:ok, %{status: 200, body: branches}} when is_list(branches) ->
        merged = acc ++ format_branches(branches)

        if length(branches) < params.per_page do
          {:ok, merged}
        else
          paginate_branches(provider, owner, repo, page + 1, merged)
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

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
            %{"sha" => sha} -> sha
            %{sha: sha} -> sha
            _ -> nil
          end
      }
    end)
  end

  @impl true
  def dispatch_workflow(%Provider{} = provider, attrs) do
    with {:ok, owner} <- fetch_required(attrs, :owner),
         {:ok, repo} <- fetch_required(attrs, :repo),
         {:ok, workflow_id} <- fetch_required(attrs, :workflow_id),
         {:ok, ref} <- fetch_required(attrs, :ref),
         payload <- %{ref: ref, inputs: fetch_inputs(attrs)},
         {:ok, response} <-
           request(
             provider,
             :post,
             "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches",
             json: payload
           ) do
      case response do
        %{status: status} when status in 200..299 -> {:ok, %{}}
        %{status: 401} -> {:error, :unauthorized}
        %{status: 403} -> {:error, :forbidden}
        %{status: 404} -> {:error, :not_found}
        %{status: status} -> {:error, {:unexpected_status, status}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def create_token(_provider, _username, _password, _attrs) do
    {:error, :not_supported}
  end

  @impl true
  def default_oauth_scope, do: "repo read:user"

  @impl true
  def authorize_url(%Provider{} = provider, redirect_uri, state) do
    with {:ok, base} <- oauth_base_url(provider),
         {:ok, client_id} <- fetch_auth_field(provider, ["client_id", :client_id]) do
      scope = fetch_scope(provider)

      query =
        %{
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: state,
          allow_signup: "false"
        }
        |> maybe_put_scope(scope)
        |> URI.encode_query()

      {:ok, "#{base}/login/oauth/authorize?#{query}"}
    end
  end

  @impl true
  def exchange_oauth_token(%Provider{} = provider, code, redirect_uri) do
    with {:ok, base} <- oauth_base_url(provider),
         {:ok, client_id} <- fetch_auth_field(provider, ["client_id", :client_id]),
         {:ok, client_secret} <- fetch_auth_field(provider, ["client_secret", :client_secret]),
         {:ok, response} <-
           Req.request(
             method: :post,
             url: "#{base}/login/oauth/access_token",
             headers: [{"accept", "application/json"}],
             json: %{
               client_id: client_id,
               client_secret: client_secret,
               code: code,
               redirect_uri: redirect_uri
             }
           ) do
      case response do
        %{status: status, body: %{"access_token" => token} = body} when status in 200..299 ->
          {:ok,
           %{
             token: token,
             token_type: Map.get(body, "token_type"),
             scope: Map.get(body, "scope"),
             refresh_token: Map.get(body, "refresh_token"),
             expires_in: Map.get(body, "expires_in")
           }}

        %{status: 401} ->
          {:error, :unauthorized}

        %{status: 400} ->
          {:error, :bad_request}

        %{status: status, body: body} ->
          {:error, {:unexpected_status, status, body}}
      end
    end
  end

  defp request(%Provider{} = provider, method, path, opts \\ []) do
    with {:ok, url} <- build_url(provider.base_url, path),
         {:ok, auth_header} <- auth_header(provider),
         {:ok, response} <-
           Req.request(
             Keyword.merge(
               [
                 method: method,
                 url: url,
                 headers: default_headers(auth_header)
               ],
               opts
             )
           ) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_headers(auth_header) do
    [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", @api_version},
      auth_header
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp auth_header(%Provider{} = provider) do
    case fetch_access_token(provider) do
      {:ok, {:pat, token}} ->
        {:ok, {"authorization", "token #{token}"}}

      {:ok, {:oauth, token}} ->
        {:ok, {"authorization", "Bearer #{token}"}}

      {:ok, {:installation, token}} ->
        {:ok, {"authorization", "Bearer #{token}"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_access_token(%Provider{} = provider) do
    case auth_mode(provider) do
      :installation -> installation_access_token(provider)
      :oauth -> oauth_token(provider)
      :pat -> pat_token(provider)
      :unknown -> {:error, :unsupported_auth_type}
    end
  end

  defp auth_mode(%Provider{auth_type: %{key: "github_app"}}), do: :installation
  defp auth_mode(%Provider{auth_type: %{key: "github_oauth"}}), do: :oauth
  defp auth_mode(%Provider{auth_type: %{key: "oauth"}}), do: :oauth
  defp auth_mode(%Provider{auth_type: %{key: "github_pat"}}), do: :pat
  defp auth_mode(%Provider{auth_type: %{key: "token"}}), do: :pat

  defp auth_mode(%Provider{auth_type: nil, auth_data: auth_data}) do
    if token_present?(auth_data) do
      :oauth
    else
      :unknown
    end
  end

  defp auth_mode(_), do: :unknown

  defp pat_token(%Provider{auth_data: auth_data}) do
    token = Map.get(auth_data || %{}, "token") || Map.get(auth_data || %{}, :token)

    case token do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, {:pat, String.trim(value)}}

      _ ->
        {:error, :missing_token}
    end
  end

  defp token_present?(auth_data) do
    auth_data = auth_data || %{}
    token = Map.get(auth_data, "token") || Map.get(auth_data, :token)
    is_binary(token) and byte_size(String.trim(token)) > 0
  end

  defp oauth_token(%Provider{auth_data: auth_data}) do
    auth_data = auth_data || %{}

    case Map.get(auth_data, "token") || Map.get(auth_data, :token) do
      value when is_binary(value) and byte_size(value) > 0 ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, :missing_token}
        else
          {:ok, {:oauth, trimmed}}
        end

      _ ->
        {:error, :missing_token}
    end
  end

  defp installation_access_token(%Provider{} = provider) do
    with {:ok, app_id} <- fetch_auth_field(provider, ["app_id", :app_id]),
         {:ok, installation_id} <-
           fetch_auth_field(provider, ["installation_id", :installation_id]),
         {:ok, pem} <- fetch_auth_field(provider, ["private_key", :private_key]),
         {:ok, jwt} <- sign_installation_jwt(app_id, pem),
         {:ok, url} <-
           build_url(provider.base_url, "/app/installations/#{installation_id}/access_tokens"),
         {:ok, response} <-
           Req.request(
             method: :post,
             url: url,
             headers: default_headers({"authorization", "Bearer #{jwt}"})
           ) do
      case response do
        %{status: status, body: %{"token" => token}} when status in 200..299 ->
          {:ok, {:installation, token}}

        %{status: 401} ->
          {:error, :unauthorized}

        %{status: 403} ->
          {:error, :forbidden}

        %{status: 404} ->
          {:error, :not_found}

        %{status: status, body: body} ->
          {:error, {:unexpected_status, status, body}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_auth_field(%Provider{auth_data: auth_data}, keys) do
    auth_data = auth_data || %{}

    value =
      Enum.find_value(keys, fn key ->
        Map.get(auth_data, key)
      end)

    case value do
      v when is_binary(v) and byte_size(v) > 0 -> {:ok, String.trim(v)}
      _ -> {:error, {:missing_auth_field, List.first(List.wrap(keys))}}
    end
  end

  defp oauth_base_url(%Provider{auth_data: auth_data, base_url: base_url}) do
    override =
      auth_data
      |> Kernel.||(%{})
      |> Map.get("oauth_base_url") ||
        Map.get(auth_data || %{}, :oauth_base_url)

    cond do
      is_binary(override) and override != "" ->
        {:ok, String.trim(override)}

      true ->
        base_url
        |> derive_oauth_host()
    end
  end

  defp derive_oauth_host(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: nil} -> {:error, :invalid_base_url}
      %URI{scheme: scheme, host: "api.github.com"} -> {:ok, "#{scheme}://github.com"}
      %URI{scheme: scheme, host: host} when is_binary(host) -> {:ok, "#{scheme}://#{host}"}
      _ -> {:error, :invalid_base_url}
    end
  rescue
    _ -> {:error, :invalid_base_url}
  end

  defp fetch_scope(%Provider{auth_data: auth_data}) do
    auth_data = auth_data || %{}

    auth_data["scope"] ||
      auth_data[:scope]
  end

  defp maybe_put_scope(map, nil), do: map
  defp maybe_put_scope(map, ""), do: map
  defp maybe_put_scope(map, scope), do: Map.put(map, :scope, scope)

  defp sign_installation_jwt(app_id, pem) do
    with {:ok, key} <- decode_private_key(pem),
         {:ok, iat} <- issued_at(),
         {:ok, payload} <- build_payload(app_id, iat),
         {:ok, unsigned} <- encode_unsigned(payload),
         {:ok, signature} <- sign(unsigned, key) do
      {:ok, unsigned <> "." <> signature}
    end
  end

  defp issued_at do
    {:ok, System.system_time(:second)}
  rescue
    _ -> {:error, :invalid_time}
  end

  defp build_payload(app_id, issued_at) do
    exp = issued_at + 600
    iat = max(issued_at - 60, 0)

    payload = %{
      "iat" => iat,
      "exp" => exp,
      "iss" => to_string(app_id)
    }

    {:ok, payload}
  end

  defp encode_unsigned(payload) do
    header = %{"alg" => "RS256", "typ" => "JWT"}

    try do
      encoded =
        [
          header |> Jason.encode!() |> Base.url_encode64(padding: false),
          payload |> Jason.encode!() |> Base.url_encode64(padding: false)
        ]
        |> Enum.join(".")

      {:ok, encoded}
    rescue
      _ -> {:error, :invalid_jwt_payload}
    end
  end

  defp sign(unsigned, key) do
    try do
      signature =
        unsigned
        |> :public_key.sign(:sha256, key)
        |> Base.url_encode64(padding: false)

      {:ok, signature}
    rescue
      _ -> {:error, :invalid_private_key}
    end
  end

  defp decode_private_key(pem) do
    pem
    |> to_string()
    |> String.trim()
    |> then(fn trimmed ->
      case trimmed |> String.to_charlist() |> :public_key.pem_decode() do
        [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
        _ -> {:error, :invalid_private_key}
      end
    end)
  rescue
    _ -> {:error, :invalid_private_key}
  end

  defp build_url(base, path) do
    case URI.parse(base) do
      %URI{scheme: nil} -> {:error, :invalid_base_url}
      %URI{} = uri -> {:ok, URI.merge(uri, path) |> URI.to_string()}
    end
  rescue
    _ -> {:error, :invalid_base_url}
  end

  defp fetch_required(map, key) do
    value =
      Map.get(map, key) ||
        Map.get(map, to_string(key))

    case value do
      v when v not in [nil, ""] -> {:ok, v}
      _ -> {:error, {:missing_required, key}}
    end
  end

  defp fetch_inputs(map) do
    Map.get(map, :inputs) || Map.get(map, "inputs") || %{}
  end
end
