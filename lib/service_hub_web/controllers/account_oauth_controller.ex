defmodule ServiceHubWeb.AccountOAuthController do
  use ServiceHubWeb, :controller

  alias ServiceHub.AccountConnections
  alias ServiceHub.OAuth
  alias ServiceHub.ProviderAdapters

  def start(conn, %{"provider" => "github"}) do
    provider = OAuth.github_provider()
    state = generate_state()
    redirect_uri = callback_url(conn, "github")

    with {:ok, url} <- ProviderAdapters.authorize_url(provider, redirect_uri, state) do
      conn
      |> put_session("account_oauth_state", put_state(conn, "github", state))
      |> redirect(external: url)
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Cannot start OAuth: #{inspect(reason)}")
        |> redirect(to: ~p"/config/providers")
    end
  end

  def callback(conn, %{"provider" => "github", "code" => code, "state" => state_param}) do
    provider = OAuth.github_provider()
    redirect_uri = callback_url(conn, "github")

    with :ok <- validate_state(conn, "github", state_param),
         {:ok, token_data} <- ProviderAdapters.exchange_oauth_token(provider, code, redirect_uri),
         {:ok, _} <- persist_connection(conn, "github", token_data) do
      conn
      |> put_flash(:info, "GitHub connected.")
      |> redirect(to: ~p"/config/providers")
    else
      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Invalid OAuth state, please retry.")
        |> redirect(to: ~p"/config/providers")

      {:error, reason} ->
        conn
        |> put_flash(:error, "OAuth failed: #{inspect(reason)}")
        |> redirect(to: ~p"/config/providers")

      _ ->
        conn
        |> put_flash(:error, "OAuth failed.")
        |> redirect(to: ~p"/config/providers")
    end
  end

  def callback(conn, %{"provider" => "github"}) do
    conn
    |> put_flash(:error, "Missing OAuth code.")
    |> redirect(to: ~p"/config/providers")
  end

  defp persist_connection(conn, provider_key, token_data) do
    scope = Map.get(token_data, :scope) || Map.get(token_data, "scope")

    attrs = %{
      "token" => Map.get(token_data, :token) || Map.get(token_data, "token"),
      "refresh_token" =>
        Map.get(token_data, :refresh_token) || Map.get(token_data, "refresh_token"),
      "scope" => scope,
      "expires_at" => expires_at(token_data),
      "metadata" => Map.drop(token_data, [:token, :refresh_token, :scope, :expires_in])
    }

    AccountConnections.upsert_connection(conn.assigns.current_scope, provider_key, attrs)
  end

  defp expires_at(token_data) do
    case Map.get(token_data, :expires_in) || Map.get(token_data, "expires_in") do
      value when is_integer(value) -> DateTime.utc_now() |> DateTime.add(value, :second)
      _ -> nil
    end
  end

  defp callback_url(_conn, provider_key) do
    path = ~p"/oauth/#{provider_key}/callback"
    ServiceHubWeb.Endpoint.url() <> path
  end

  defp generate_state do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp put_state(conn, provider_key, state) do
    states = get_session(conn, "account_oauth_state") || %{}
    Map.put(states, provider_key, state)
  end

  defp validate_state(conn, provider_key, incoming_state) do
    expected =
      conn
      |> get_session("account_oauth_state")
      |> Kernel.||(%{})
      |> Map.get(provider_key)

    if expected && expected == incoming_state do
      :ok
    else
      {:error, :invalid_state}
    end
  end
end
