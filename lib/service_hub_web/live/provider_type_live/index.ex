defmodule ServiceHubWeb.ProviderTypeLive.Index do
  use ServiceHubWeb, :live_view

  alias ServiceHub.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-semibold text-base-content">Provider Types</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Configure available provider types (GitHub, Gitea, etc.)
          </p>
        </div>
        <.button variant="primary" navigate={~p"/config/provider-types/new"}>
          <.icon name="hero-plus" class="w-4 h-4" /> New Type
        </.button>
      </div>

      <div class="grid gap-4">
        <div
          :for={{id, provider_type} <- @streams.provider_types}
          id={id}
          class="border border-base-300 rounded-lg p-4 hover:border-base-content/20 transition-colors cursor-pointer"
          phx-click={JS.navigate(~p"/config/provider-types/#{provider_type}/edit")}
        >
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center gap-3">
                <h3 class="font-medium text-base-content">{provider_type.name}</h3>
                <span class="text-xs px-2 py-1 rounded bg-base-200 text-base-content/70 font-mono">
                  {provider_type.key}
                </span>
              </div>
              <div :if={map_size(provider_type.required_fields) > 0} class="mt-2">
                <p class="text-xs text-base-content/60 mb-1">Required fields:</p>
                <div class="flex flex-wrap gap-2">
                  <span
                    :for={{field, _} <- provider_type.required_fields}
                    class="text-xs px-2 py-1 rounded bg-base-100 border border-base-300 text-base-content/80"
                  >
                    {field}
                  </span>
                </div>
              </div>
            </div>
            <button
              phx-click={JS.push("delete", value: %{id: provider_type.id}) |> hide("##{id}")}
              data-confirm="Are you sure? This will affect all providers using this type."
              class="p-2 hover:bg-error/10 hover:text-error rounded transition-colors"
              onclick="event.stopPropagation();"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>

        <div
          :if={Enum.empty?(@streams.provider_types.inserts)}
          class="border border-dashed border-base-300 rounded-lg p-8 text-center"
        >
          <.icon name="hero-document-text" class="w-12 h-12 mx-auto text-base-content/30 mb-2" />
          <p class="text-base-content/60">No provider types configured yet</p>
          <.button variant="primary" navigate={~p"/config/provider-types/new"} class="mt-4">
            Create your first provider type
          </.button>
        </div>
      </div>

      <div class="mt-6 p-4 bg-base-200/50 rounded-lg border border-base-300">
        <h3 class="text-sm font-medium text-base-content mb-2">About Provider Types</h3>
        <p class="text-xs text-base-content/70">
          Provider types define the kind of code hosting platform (GitHub, Gitea, GitLab, etc.).
          Each type specifies which fields are required when creating a provider instance.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Providers.subscribe_provider_types(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Provider types")
     |> stream(:provider_types, list_provider_types(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    provider_type = Providers.get_provider_type!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_provider_type(socket.assigns.current_scope, provider_type)

    {:noreply, stream_delete(socket, :provider_types, provider_type)}
  end

  @impl true
  def handle_info({type, %ServiceHub.Providers.ProviderType{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :provider_types, list_provider_types(socket.assigns.current_scope),
       reset: true
     )}
  end

  defp list_provider_types(current_scope) do
    Providers.list_provider_types(current_scope)
  end
end
