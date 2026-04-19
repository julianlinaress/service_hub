defmodule ServiceHub.Checks.Health do
  @moduledoc """
  Health check engine. Health checks are required for every deployment, and
  expectations (allowed statuses, expected JSON fragment) are configurable per
  deployment.
  """
  require Logger
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service
  alias ServiceHub.Repo

  @default_allowed_statuses [200]
  @default_timeout 5_000

  def run(%Deployment{} = deployment, %Service{} = service) do
    now = DateTime.utc_now(:second)
    expectation = deployment.healthcheck_expectation || %{}

    allowed_statuses =
      Map.get(expectation, "allowed_statuses") || Map.get(expectation, :allowed_statuses)

    allowed_statuses = allowed_statuses || @default_allowed_statuses
    expected_json = Map.get(expectation, "expected_json") || Map.get(expectation, :expected_json)

    url =
      (service.healthcheck_endpoint_template || "https://{{host}}/api/health")
      |> interpolate_host(deployment.host)

    req_opts = [
      method: :get,
      url: url,
      headers: build_headers(deployment),
      receive_timeout: @default_timeout,
      connect_options: [timeout: @default_timeout]
    ]

    result =
      case http_client().request(req_opts) do
        {:ok, %{status: status} = response} ->
          Logger.info("Health check response url=#{url} status=#{status}")
          classify_response(status, response, allowed_statuses, expected_json)

        {:error, reason} ->
          Logger.info("Health check error url=#{url} error=#{inspect(reason)}")
          {:down, {:error, reason}}
      end

    new_status =
      case result do
        {:ok, _details} -> "ok"
        {:warning, _details} -> "warning"
        {:down, _details} -> "down"
      end

    changeset =
      Ecto.Changeset.change(deployment, %{
        last_health_status: new_status,
        last_health_checked_at: now
      })

    {:ok, updated} = Repo.update(changeset)

    case result_outcome(result) do
      {:ok, _details} ->
        {:ok, Repo.preload(updated, service: :provider)}

      {:warning, reason} ->
        {:warning, reason, Repo.preload(updated, service: :provider)}

      {:error, reason} ->
        {:error, reason, Repo.preload(updated, service: :provider)}
    end
  end

  defp classify_response(status, %{body: body}, allowed, expected_json) do
    cond do
      status in (allowed || @default_allowed_statuses) and json_ok?(body, expected_json) ->
        {:ok, %{status: status}}

      status >= 500 ->
        {:down, {:unexpected_status, status}}

      true ->
        {:warning, {:unexpected_status, status}}
    end
  end

  defp json_ok?(_body, nil), do: true

  defp json_ok?(body, expected) when is_map(expected) do
    case body do
      %{} = map -> map_contains?(map, expected)
      _ -> false
    end
  end

  defp json_ok?(_, _), do: true

  defp map_contains?(body, expected) do
    Enum.all?(expected, fn {key, value} ->
      case Map.fetch(body, key) do
        {:ok, ^value} -> true
        {:ok, submap} when is_map(submap) and is_map(value) -> map_contains?(submap, value)
        _ -> false
      end
    end)
  end

  defp build_headers(%Deployment{api_key: nil}), do: []

  defp build_headers(%Deployment{api_key: api_key}) do
    [{"x-api-key", api_key}]
  end

  defp interpolate_host(template, host) do
    clean_host =
      host
      |> to_string()
      |> String.trim()
      |> String.replace_leading("https://", "")
      |> String.replace_leading("http://", "")
      |> encode_idn_with_path()

    String.replace(template, "{{host}}", clean_host)
  end

  # Convert internationalized domain names (IDN) to ASCII-compatible encoding (Punycode)
  # Handles hosts with path components like "example.com/path"
  # e.g., "café.example.com/path" -> "xn--caf-dma.example.com/path"
  defp encode_idn_with_path(host) do
    case String.split(host, "/", parts: 2) do
      [domain] ->
        # No path component, just encode the domain
        encode_idn(domain)

      [domain, path] ->
        # Has path component, encode only the domain and rejoin
        encoded_domain = encode_idn(domain)
        "#{encoded_domain}/#{path}"
    end
  end

  defp encode_idn(domain) do
    domain
    |> to_charlist()
    |> :idna.encode()
    |> to_string()
  rescue
    # If idna library throws an error, use the original domain
    _ -> domain
  end

  defp result_outcome({:ok, _details}), do: {:ok, :healthy}
  defp result_outcome({:warning, reason}), do: {:warning, reason}
  defp result_outcome({:down, reason}), do: {:error, reason}

  defp http_client do
    Application.get_env(:service_hub, :http_client, Req)
  end
end
