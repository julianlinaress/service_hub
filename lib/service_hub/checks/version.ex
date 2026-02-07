defmodule ServiceHub.Checks.Version do
  @moduledoc """
  Version check engine. Version checks are optional per deployment and can carry
  per-deployment expectations for parsing/validation.
  """
  require Logger
  alias ServiceHub.Deployments.Deployment
  alias ServiceHub.Services.Service
  alias ServiceHub.Repo

  @default_allowed_statuses [200]
  @default_timeout 5_000

  def run(%Deployment{version_check_enabled: false} = deployment, %Service{}) do
    {:skipped, Repo.preload(deployment, service: :provider)}
  end

  def run(%Deployment{} = deployment, %Service{} = service) do
    now = DateTime.utc_now(:second)
    expectation = deployment.version_expectation || %{}

    allowed_statuses =
      Map.get(expectation, "allowed_statuses") || Map.get(expectation, :allowed_statuses)

    allowed_statuses = allowed_statuses || @default_allowed_statuses
    field = Map.get(expectation, "field") || Map.get(expectation, :field) || "version"

    url =
      (service.version_endpoint_template || "https://{{host}}/api/version")
      |> interpolate_host(deployment.host)

    req_opts = [
      method: :get,
      url: url,
      headers: build_headers(deployment),
      receive_timeout: @default_timeout,
      connect_options: [timeout: @default_timeout]
    ]

    result =
      case Req.request(req_opts) do
        {:ok, %{status: status} = response} ->
          Logger.info("Version check response url=#{url} status=#{status}")

          if status in allowed_statuses do
            log_parsing(field, response.body)
            parse_version(response.body, field)
          else
            {:error, {:unexpected_status, status}}
          end

        {:error, reason} ->
          Logger.info("Version check error url=#{url} error=#{inspect(reason)}")
          {:error, reason}
      end

    case result do
      {:ok, version} ->
        changeset =
          Ecto.Changeset.change(deployment, %{
            current_version: version,
            last_version_checked_at: now
          })

        {:ok, updated} = Repo.update(changeset)
        {:ok, Repo.preload(updated, service: :provider)}

      {:error, reason} ->
        changeset =
          Ecto.Changeset.change(deployment, %{
            last_version_checked_at: now
          })

        {:ok, updated} = Repo.update(changeset)
        {:error, reason, Repo.preload(updated, service: :provider)}
    end
  end

  defp parse_version(body, field) when is_map(body) do
    case Map.fetch(body, field) do
      {:ok, version} when is_binary(version) ->
        Logger.info("Version check field_found=#{field} value=#{version}")
        {:ok, version}

      {:ok, version} ->
        Logger.info("Version check field_found=#{field} value=#{inspect(version)}")
        {:ok, to_string(version)}

      :error ->
        Logger.info("Version check missing_field=#{field}")
        {:error, :missing_version_field}
    end
  end

  defp parse_version(body, _field) when is_binary(body) do
    version =
      body
      |> String.trim()
      |> String.split("\n", trim: true)
      |> List.first()

    if version in [nil, ""] do
      Logger.info("Version check empty text body")
      {:error, :empty_version}
    else
      Logger.info("Version check text_version=#{version}")
      {:ok, version}
    end
  end

  defp parse_version(_body, _field), do: {:error, :unparseable_version}

  defp log_parsing(field, body) when is_map(body) do
    Logger.info("Version check parsing field=#{field} from JSON body")
  end

  defp log_parsing(field, body) when is_binary(body) do
    snippet =
      body
      |> String.slice(0, 200)
      |> String.replace("\n", "\\n")

    Logger.info("Version check parsing field=#{field} from text body snippet=#{snippet}")
  end

  defp log_parsing(field, _body) do
    Logger.info("Version check parsing field=#{field} from text body")
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

    String.replace(template, "{{host}}", clean_host)
  end
end
