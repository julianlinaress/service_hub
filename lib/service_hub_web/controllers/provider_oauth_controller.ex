defmodule ServiceHubWeb.ProviderOAuthController do
  use ServiceHubWeb, :controller

  alias ServiceHub.ProviderAdapters
  alias ServiceHub.Providers

  def start(conn, %{"id" => id}) do
    provider = Providers.get_provider!(conn.assigns.current_scope, id)

    with :ok <- ensure_oauth_auth_type(provider),
         redirect_uri <- oauth_callback_url(conn, provider),
         state <- generate_state(),
         {:ok, url} <- ProviderAdapters.authorize_url(provider, redirect_uri, state) do
      conn
      |> put_session("oauth_state", put_state(conn, provider.id, state))
      |> redirect(external: url)
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Cannot start OAuth: #{inspect(reason)}")
        |> redirect(to: ~p"/providers/#{provider}")
    end
  end

  def callback(conn, %{"id" => id, "code" => code, "state" => state_param}) do
    provider = Providers.get_provider!(conn.assigns.current_scope, id)

    with :ok <- ensure_oauth_auth_type(provider),
         :ok <- validate_state(conn, provider.id, state_param),
         redirect_uri <- oauth_callback_url(conn, provider),
         {:ok, token_data} <-
           ProviderAdapters.exchange_oauth_token(provider, code, redirect_uri),
         {:ok, _provider} <- persist_tokens(conn, provider, token_data) do
      conn
      |> put_flash(:info, "OAuth connection saved.")
      |> redirect(to: ~p"/providers/#{provider}")
    else
      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Invalid OAuth state, please retry.")
        |> redirect(to: ~p"/providers/#{provider}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "OAuth failed: #{inspect(reason)}")
        |> redirect(to: ~p"/providers/#{provider}")

      _ ->
        conn
        |> put_flash(:error, "OAuth failed.")
        |> redirect(to: ~p"/providers/#{provider}")
    end
  end

  def callback(conn, %{"id" => id}) do
    provider = Providers.get_provider!(conn.assigns.current_scope, id)

    conn
    |> put_flash(:error, "Missing OAuth code.")
    |> redirect(to: ~p"/providers/#{provider}")
  end

  defp ensure_oauth_auth_type(%{auth_type: %{key: key}})
       when key in ["github_oauth", "oauth"],
       do: :ok

  defp ensure_oauth_auth_type(_), do: {:error, :unsupported_auth_type}

  defp oauth_callback_url(_conn, provider) do
    path = ~p"/providers/#{provider}/oauth/callback"
    ServiceHubWeb.Endpoint.url() <> path
  end

  defp generate_state do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp put_state(conn, provider_id, state) do
    states = get_session(conn, "oauth_state") || %{}
    Map.put(states, to_string(provider_id), state)
  end

  defp validate_state(conn, provider_id, incoming_state) do
    expected =
      conn
      |> get_session("oauth_state")
      |> Kernel.||(%{})
      |> Map.get(to_string(provider_id))

    if expected && expected == incoming_state do
      :ok
    else
      {:error, :invalid_state}
    end
  end

  defp persist_tokens(conn, provider, token_data) do
    expires_at =
      token_data
      |> Map.get(:expires_in)
      |> case do
        value when is_integer(value) ->
          DateTime.utc_now() |> DateTime.add(value, :second)

        _ ->
          nil
      end

    attrs =
      provider.auth_data
      |> Kernel.||(%{})
      |> Map.merge(%{
        "token" => token_data[:token],
        "token_type" => token_data[:token_type],
        "scope" => token_data[:scope],
        "refresh_token" => token_data[:refresh_token],
        "expires_at" => expires_at
      })

    Providers.save_provider_auth_data(conn.assigns.current_scope, provider, attrs)
  end
end
