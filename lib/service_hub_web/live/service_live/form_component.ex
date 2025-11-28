defmodule ServiceHubWeb.ServiceLive.FormComponent do
  use ServiceHubWeb, :live_component

  alias ServiceHub.Services

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-md">
      <div class="card-body space-y-6">
        <div class="flex items-center justify-between">
          <h3 class="card-title">{@title}</h3>
          <.button patch={@return_to}>
            <.icon name="hero-x-mark" />
          </.button>
        </div>

        <.form
          for={@form}
          id="service-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Display name" />
            <.input field={@form[:default_ref]} type="text" label="Default ref (optional)" />
            <.input field={@form[:owner]} type="text" label="Repo owner/org" />
            <.input field={@form[:repo]} type="text" label="Repository name" />
            <.input
              field={@form[:version_endpoint_template]}
              type="text"
              label="Version endpoint template"
              placeholder="https://{{host}}/api/version"
            />
            <.input
              field={@form[:healthcheck_endpoint_template]}
              type="text"
              label="Healthcheck endpoint template"
              placeholder="https://{{host}}/api/health"
            />
          </div>
          <footer class="mt-6 flex items-center gap-3">
            <.button variant="primary" phx-disable-with="Saving...">Save service</.button>
            <.button patch={@return_to}>Cancel</.button>
          </footer>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    changeset =
      Services.change_service(
        assigns.current_scope,
        assigns.service,
        Map.get(assigns, :params, %{})
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"service" => params}, socket) do
    changeset =
      socket.assigns
      |> Map.take([:current_scope, :service])
      |> then(fn %{current_scope: scope, service: service} ->
        Services.change_service(scope, service, params)
      end)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"service" => params}, socket) do
    save_service(socket, socket.assigns.action, params)
  end

  defp save_service(socket, :new_service, params) do
    params = Map.put(params, "provider_id", socket.assigns.provider.id)

    case Services.create_service(socket.assigns.current_scope, params) do
      {:ok, service} ->
        notify_parent({:saved, service})

        {:noreply,
         socket
         |> put_flash(:info, "Service created")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create service: #{inspect(reason)}")}
    end
  end

  defp save_service(socket, :edit_service, params) do
    case Services.update_service(socket.assigns.current_scope, socket.assigns.service, params) do
      {:ok, service} ->
        notify_parent({:saved, service})

        {:noreply,
         socket
         |> put_flash(:info, "Service updated")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not update service: #{inspect(reason)}")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
