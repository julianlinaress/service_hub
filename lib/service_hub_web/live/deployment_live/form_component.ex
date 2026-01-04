defmodule ServiceHubWeb.DeploymentLive.FormComponent do
  @moduledoc """
  Deployment form. Creating a deployment records host/env metadata but does not
  install or deploy any code.
  """
  use ServiceHubWeb, :live_component
  alias Phoenix.LiveView.JS
  alias ServiceHub.Deployments

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {if @action == :new, do: "New Deployment", else: "Edit Deployment"}
        <:subtitle>
          Define where this service runs. Creating a deployment does not install the service.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="deployment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input field={@form[:name]} label="Name" />
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <.input field={@form[:env]} label="Environment" />
            <.input field={@form[:host]} label="Host (without protocol)" />
          </div>
          <.input field={@form[:api_key]} label="API Key (optional)" />

          <div class="rounded border border-base-300 p-3 space-y-3">
            <p class="text-sm font-semibold">Health expectations (required)</p>
            <.input
              name="deployment[health_allowed_statuses]"
              label="Allowed status codes"
              value={@health_allowed_statuses}
              placeholder="200,204"
            />
            <.input
              name="deployment[health_expected_json]"
              label="Expected JSON (optional, snippet)"
              type="textarea"
              value={@health_expected_json}
              placeholder={"{\"status\":\"ok\"}"}
            />
          </div>

          <div class="rounded border border-base-300 p-3 space-y-3">
            <div class="flex items-center gap-2">
              <.input
                field={@form[:version_check_enabled]}
                type="checkbox"
                label="Enable version checks"
              />
              <p class="text-xs text-base-content/60">
                Optional; configure per-deployment parsing if enabled.
              </p>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input
                name="deployment[version_allowed_statuses]"
                label="Allowed status codes"
                value={@version_allowed_statuses}
                placeholder="200"
              />
              <.input
                name="deployment[version_field]"
                label="JSON field to read (fallback to plain text)"
                value={@version_field}
                placeholder="version"
              />
            </div>
          </div>

          <div class="flex items-center gap-3">
            <.button phx-disable-with="Saving...">Save</.button>
            <.button type="button" variant="ghost" phx-click={JS.push("cancel", target: @myself)}>
              Cancel
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{deployment: deployment} = assigns, socket) do
    changeset = Deployments.change_deployment(assigns.current_scope, deployment)

    health_allowed_statuses =
      deployment.healthcheck_expectation
      |> Map.get("allowed_statuses")
      |> sanitize_statuses()
      |> case do
        [] -> "200"
        list -> Enum.map(list, &Integer.to_string/1) |> Enum.join(",")
      end

    health_expected_json =
      deployment.healthcheck_expectation
      |> Kernel.||(%{})
      |> Map.get("expected_json")
      |> encode_json_safe()

    version_allowed_statuses =
      deployment.version_expectation
      |> Map.get("allowed_statuses")
      |> sanitize_statuses()
      |> case do
        [] -> "200"
        list -> Enum.map(list, &Integer.to_string/1) |> Enum.join(",")
      end

    version_field =
      deployment.version_expectation
      |> Map.get("field")
      |> case do
        nil -> ""
        val -> to_string(val)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))
     |> assign(:health_allowed_statuses, health_allowed_statuses)
     |> assign(:health_expected_json, health_expected_json)
     |> assign(:version_allowed_statuses, version_allowed_statuses)
     |> assign(:version_field, version_field)}
  end

  @impl true
  def handle_event("validate", %{"deployment" => params}, socket) do
    params = normalize_expectations(params, socket.assigns.deployment)

    changeset =
      Deployments.change_deployment(
        socket.assigns.current_scope,
        socket.assigns.deployment,
        params
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign_form_aux(params)}
  end

  @impl true
  def handle_event("save", %{"deployment" => params}, socket) do
    params = normalize_expectations(params, socket.assigns.deployment)

    save_deployment(socket, socket.assigns.action, params)
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {:deployment_modal, :close})
    {:noreply, socket}
  end

  defp save_deployment(socket, :new, params) do
    case Deployments.create_deployment(socket.assigns.current_scope, params) do
      {:ok, deployment} ->
        notify_parent({:saved, deployment})
        send(self(), {:deployment_modal, :close})

        {:noreply,
         socket
         |> put_flash(:info, "Deployment created")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_deployment(socket, :edit, params) do
    case Deployments.update_deployment(
           socket.assigns.current_scope,
           socket.assigns.deployment,
           params
         ) do
      {:ok, deployment} ->
        notify_parent({:saved, deployment})
        send(self(), {:deployment_modal, :close})

        {:noreply,
         socket
         |> put_flash(:info, "Deployment updated")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp normalize_expectations(params, deployment) do
    params
    |> Map.put("service_id", deployment.service_id || params["service_id"])
    |> Map.put("healthcheck_expectation", %{
      "allowed_statuses" => split_codes(Map.get(params, "health_allowed_statuses")),
      "expected_json" => decode_json(Map.get(params, "health_expected_json"))
    })
    |> Map.put("version_expectation", %{
      "allowed_statuses" => split_codes(Map.get(params, "version_allowed_statuses")),
      "field" => blank_to_nil(Map.get(params, "version_field"))
    })
  end

  defp split_codes(nil), do: []
  defp split_codes(""), do: []

  defp split_codes(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_int(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp sanitize_statuses(nil), do: []

  defp sanitize_statuses(list) when is_list(list) do
    list
    |> Enum.map(&coerce_status/1)
    |> Enum.reject(&is_nil/1)
  end

  defp sanitize_statuses(_), do: []

  defp coerce_status(value) when is_integer(value), do: value

  defp coerce_status(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp coerce_status(_), do: nil

  defp encode_json_safe(%{} = map) do
    case Jason.encode(map) do
      {:ok, json} -> json
      _ -> inspect(map)
    end
  rescue
    _ -> ""
  end

  defp encode_json_safe(value) when is_binary(value) do
    case :unicode.characters_to_binary(value, :utf8, :utf8) do
      safe when is_binary(safe) -> safe
    end
  rescue
    _ -> ""
  end

  defp encode_json_safe(_), do: ""

  defp decode_json(nil), do: nil
  defp decode_json(""), do: nil

  defp decode_json(str) do
    case Jason.decode(str) do
      {:ok, %{} = map} -> map
      _ -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp assign_form_aux(socket, params) do
    socket
    |> assign(:health_allowed_statuses, Map.get(params, "health_allowed_statuses", ""))
    |> assign(:health_expected_json, Map.get(params, "health_expected_json", ""))
    |> assign(:version_allowed_statuses, Map.get(params, "version_allowed_statuses", ""))
    |> assign(:version_field, Map.get(params, "version_field", ""))
  end
end
