defmodule ServiceHubWeb.ServiceLive.FormComponent do
  use ServiceHubWeb, :live_component

  alias Phoenix.LiveView.AsyncResult
  alias ServiceHub.ProviderAdapters
  alias ServiceHub.Services

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.form
        for={@form}
        id="service-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-6">
          <%!-- Repository --%>
          <div>
            <.async_result :let={repos} assign={@repo_async}>
              <:loading>
                <div class="fieldset mb-2">
                  <label>
                    <span class="label mb-1">Repository</span>
                    <div class="skeleton h-10 w-full"></div>
                  </label>
                </div>
              </:loading>
              <:failed :let={reason}>
                <div class="text-sm text-error">
                  Failed to load repositories: {format_repo_error(reason)}
                </div>
              </:failed>
              <.input
                field={@form[:repo_full_name]}
                type="select"
                label="Repository"
                options={repo_options(repos)}
                prompt="Select a repository"
              />
            </.async_result>
          </div>

          <%!-- Service details --%>
          <div class="grid gap-4 md:grid-cols-2">
            <.input field={@form[:name]} type="text" label="Display name" />
            
            <%!-- Branch selector --%>
            <div>
              <.async_result :let={branches} assign={@branch_async}>
                <:loading>
                  <div class="fieldset mb-2">
                    <label>
                      <span class="label mb-1">Default branch</span>
                      <div class="skeleton h-10 w-full"></div>
                    </label>
                  </div>
                </:loading>
                <:failed :let={_reason}>
                  <.input field={@form[:default_ref]} type="text" label="Default branch" placeholder="main" />
                </:failed>
                <.input
                  field={@form[:default_ref]}
                  type="select"
                  label="Default branch"
                  options={branch_options(branches)}
                  prompt="Select a branch"
                />
              </.async_result>
            </div>
          </div>

          <%!-- Endpoints --%>
          <div class="grid gap-4 md:grid-cols-2">
            <.input
              field={@form[:version_endpoint_template]}
              type="text"
              label="Version endpoint"
              placeholder="https://{{host}}/api/version"
            />
            <.input
              field={@form[:healthcheck_endpoint_template]}
              type="text"
              label="Health endpoint"
              placeholder="https://{{host}}/api/health"
            />
          </div>
        </div>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          <.button navigate={@return_to} variant="ghost">Cancel</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    params = Map.get(assigns, :params, %{})
    changeset = build_changeset(assigns, params)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form_params, params)
     |> assign(:form, to_form(changeset))
     |> ensure_repo_async_started()
     |> ensure_branch_async(changeset)}
  end

  @impl true
  def handle_event("validate", %{"service" => params}, socket) do
    changeset =
      socket.assigns
      |> Map.take([:current_scope, :service, :provider])
      |> Map.put(:params, params)
      |> build_changeset()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form_params, params)
     |> assign(:form, to_form(changeset))
     |> ensure_branch_async(changeset)}
  end

  def handle_event("save", %{"service" => params}, socket) do
    save_service(socket, socket.assigns.action, params)
  end

  @impl true
  def handle_async(:repos, {:ok, {:ok, repos}}, socket) do
    {:noreply, assign(socket, :repo_async, AsyncResult.ok(repos))}
  end

  def handle_async(:repos, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :repo_async, AsyncResult.failed(socket.assigns.repo_async, reason))}
  end

  def handle_async(:repos, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, :repo_async, AsyncResult.failed(socket.assigns.repo_async, {:exit, reason}))}
  end

  def handle_async(:repos, _, socket) do
    {:noreply,
     assign(socket, :repo_async, AsyncResult.failed(socket.assigns.repo_async, :unknown))}
  end

  def handle_async({:branches, repo_full}, {:ok, {:ok, branches}}, socket) do
    if socket.assigns[:branch_repo_ref] == repo_full do
      {:noreply, assign(socket, :branch_async, AsyncResult.ok(branches))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:branches, repo_full}, {:ok, {:error, reason}}, socket) do
    if socket.assigns[:branch_repo_ref] == repo_full do
      {:noreply, assign(socket, :branch_async, AsyncResult.failed(socket.assigns.branch_async, reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:branches, _repo_full}, {:exit, reason}, socket) do
    {:noreply, assign(socket, :branch_async, AsyncResult.failed(socket.assigns.branch_async, {:exit, reason}))}
  end

  def handle_async({:branches, _repo_full}, _, socket) do
    {:noreply, assign(socket, :branch_async, AsyncResult.failed(socket.assigns.branch_async, :unknown))}
  end

  defp save_service(socket, action, params) when action in [:new, :new_service] do
    params =
      params
      |> normalize_repo_params()
      |> Map.put("provider_id", socket.assigns.provider.id)

    case Services.create_service(socket.assigns.current_scope, params) do
      {:ok, service} ->
        notify_parent({:saved, service})

        {:noreply,
         socket
         |> put_flash(:info, "Service created")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create service: #{inspect(reason)}")}
    end
  end

  defp save_service(socket, action, params) when action in [:edit, :edit_service] do
    case Services.update_service(
           socket.assigns.current_scope,
           socket.assigns.service,
           normalize_repo_params(params)
         ) do
      {:ok, service} ->
        notify_parent({:saved, service})

        {:noreply,
         socket
         |> put_flash(:info, "Service updated")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not update service: #{inspect(reason)}")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp build_changeset(%{params: params} = assigns) do
    build_changeset(assigns, params)
  end

  defp build_changeset(%{current_scope: scope, service: service}, params) do
    params
    |> maybe_seed_repo_full_name(service)
    |> normalize_repo_params()
    |> then(&Services.change_service(scope, service, &1))
    |> maybe_set_repo_full_name(service)
    |> case do
      %Ecto.Changeset{} = cs -> cs
      other -> other
    end
  end

  defp ensure_repo_async_started(socket) do
    repo_async = socket.assigns[:repo_async] || AsyncResult.loading()
    socket = assign(socket, :repo_async, repo_async)
    provider = socket.assigns.provider

    if repo_async.loading do
      start_async(socket, :repos, fn ->
        ProviderAdapters.list_repositories(provider)
      end)
    else
      socket
    end
  end

  defp ensure_branch_async(socket, changeset) do
    repo_full = Ecto.Changeset.get_field(changeset, :repo_full_name)
    current_ref = socket.assigns[:branch_repo_ref]
    
    cond do
      is_nil(repo_full) ->
        socket
        |> assign(:branch_repo_ref, nil)
        |> assign(:branch_async, AsyncResult.ok([]))

      repo_full == current_ref ->
        socket

      true ->
        {owner, repo} = parse_full_name(repo_full)
        
        if is_nil(owner) or is_nil(repo) do
          socket
          |> assign(:branch_repo_ref, repo_full)
          |> assign(:branch_async, AsyncResult.ok([]))
        else
          provider = socket.assigns.provider
          socket
          |> assign(:branch_repo_ref, repo_full)
          |> assign(:branch_async, AsyncResult.loading())
          |> start_async({:branches, repo_full}, fn ->
            ProviderAdapters.list_branches(provider, owner, repo)
          end)
        end
    end
  end

  defp repo_options(repos) do
    Enum.map(repos, fn repo ->
      label = repo_label(repo)
      value = repo_value(repo)
      {label, value}
    end)
  end

  defp repo_label(repo) do
    full_name = repo_value(repo)

    if repo[:private] do
      "#{full_name} (private)"
    else
      full_name
    end
  end

  defp repo_value(repo) do
    repo[:full_name] || build_full_name(repo[:owner], repo[:name])
  end

  defp format_repo_error(:unauthorized), do: "Unauthorized"
  defp format_repo_error(:forbidden), do: "Forbidden"
  defp format_repo_error(:not_found), do: "Not found"
  defp format_repo_error(:unsupported_auth_type), do: "Unsupported auth type"
  defp format_repo_error(:missing_token), do: "Missing token"
  defp format_repo_error({:unexpected_status, status}), do: "Unexpected response (#{status})"
  defp format_repo_error(reason), do: inspect(reason)

  defp normalize_repo_params(params) do
    params
    |> Map.new()
    |> then(fn attrs ->
      case parse_full_name(attrs["repo_full_name"] || attrs[:repo_full_name]) do
        {owner, repo} when is_binary(owner) and is_binary(repo) ->
          attrs
          |> Map.put("owner", owner)
          |> Map.put("repo", repo)

        _ ->
          attrs
      end
    end)
  end

  defp parse_full_name(full) when is_binary(full) do
    case String.split(full, "/", parts: 2) do
      [owner, repo] when owner != "" and repo != "" -> {owner, repo}
      _ -> {nil, nil}
    end
  end

  defp parse_full_name(_), do: {nil, nil}

  defp maybe_seed_repo_full_name(params, service) do
    cond do
      Map.has_key?(params, "repo_full_name") ->
        params

      Map.has_key?(params, :repo_full_name) ->
        params

      is_binary(service.owner) and service.owner != "" and is_binary(service.repo) and
          service.repo != "" ->
        Map.put(params, "repo_full_name", "#{service.owner}/#{service.repo}")

      true ->
        params
    end
  end

  defp maybe_set_repo_full_name(%Ecto.Changeset{} = changeset, _service) do
    owner = Ecto.Changeset.get_field(changeset, :owner)
    repo = Ecto.Changeset.get_field(changeset, :repo)
    full_name = build_full_name(owner, repo)

    case full_name do
      nil -> changeset
      value -> Ecto.Changeset.put_change(changeset, :repo_full_name, value)
    end
  end

  defp maybe_set_repo_full_name(changeset, _service), do: changeset

  defp build_full_name(owner, repo)
       when is_binary(owner) and owner != "" and is_binary(repo) and repo != "" do
    "#{owner}/#{repo}"
  end

  defp build_full_name(_, _), do: nil

  defp branch_options(branches) do
    Enum.map(branches, fn branch ->
      {branch[:name] || "unknown", branch[:name]}
    end)
  end
end
