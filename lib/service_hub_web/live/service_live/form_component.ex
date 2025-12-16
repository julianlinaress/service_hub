defmodule ServiceHubWeb.ServiceLive.FormComponent do
  use ServiceHubWeb, :live_component

  alias Phoenix.LiveView
  alias Phoenix.LiveView.AsyncResult
  alias ServiceHub.ProviderAdapters
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
          <div class="space-y-6">
            <div class="grid gap-4 md:grid-cols-2">
              <div class="space-y-3 rounded border border-base-300/70 p-4">
                <p class="text-sm font-semibold text-base-content">Repository</p>
                <p class="text-sm text-base-content/70">
                  Pick from the provider connection. This will set owner/repo automatically.
                </p>
                <.async_result :let={repos} assign={@repo_async}>
                  <:loading>
                    <p class="text-sm text-base-content/70">Loading repositories...</p>
                  </:loading>
                  <:failed :let={reason}>
                    <p class="text-sm text-warning">
                      Could not load repositories: {format_repo_error(reason)}
                    </p>
                  </:failed>
                  <.input
                    field={@form[:repo_full_name]}
                    type="select"
                    label="Repository"
                    options={repo_options(repos)}
                    prompt="Select a repository"
                  />
                  <p :if={repos == []} class="text-sm text-base-content/70">
                    No repositories with the required permissions were found for this provider.
                  </p>
                </.async_result>
              </div>

              <div class="space-y-3 rounded border border-base-300/70 p-4">
                <p class="text-sm font-semibold text-base-content">Branch / ref</p>
                <p class="text-sm text-base-content/70">
                  Choose a branch from the fetched list or type a custom ref below.
                </p>
                <.async_result :let={branches} assign={@branch_async}>
                  <:loading>
                    <p class="text-sm text-base-content/70">Loading branches...</p>
                  </:loading>
                  <:failed :let={reason}>
                    <p class="text-sm text-warning">
                      Could not load branches: {format_branch_error(reason)}
                    </p>
                  </:failed>
                  <.input
                    name="branch_select"
                    type="select"
                    label="Branches (optional)"
                    options={branch_options(branches)}
                    prompt="Select a branch"
                    phx-change="select-branch"
                    phx-target={@myself}
                    value={branch_select_value(@form)}
                  />
                  <p :if={@branch_repo_ref} class="text-xs text-base-content/60">
                    Branches loaded for {@branch_repo_ref}.
                  </p>
                </.async_result>
                <.input field={@form[:default_ref]} type="text" label="Default ref (optional)" />
              </div>
            </div>

            <div class="space-y-3 rounded border border-base-300/70 p-4">
              <p class="text-sm font-semibold text-base-content">Service details</p>
              <div class="grid gap-4 md:grid-cols-2">
                <.input field={@form[:name]} type="text" label="Display name" />
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
            </div>
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
    params = Map.get(assigns, :params, %{})
    changeset = build_changeset(assigns, params)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form_params, params)
     |> assign(:form, to_form(changeset))
     |> ensure_repo_async_started()
     |> maybe_start_branch_async(changeset)}
  end

  @impl true
  def handle_event("validate", %{"service" => params}, socket) do
    changeset =
      socket.assigns
      |> Map.take([:current_scope, :service, :provider])
      |> Map.put(:params, params)
      |> build_changeset()
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form_params, params)
      |> assign(:form, to_form(changeset))
      |> maybe_start_branch_async(changeset)

    {:noreply, socket}
  end

  def handle_event("save", %{"service" => params}, socket) do
    save_service(socket, socket.assigns.action, params)
  end

  def handle_event("select-branch", %{"branch_select" => branch}, socket) do
    branch = normalize_branch(branch)

    params =
      socket.assigns.form_params
      |> Map.new()
      |> Map.put("default_ref", branch)

    changeset =
      socket.assigns
      |> Map.take([:current_scope, :service, :provider])
      |> Map.put(:params, params)
      |> build_changeset()
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign(:form, to_form(changeset))}
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
    if socket.assigns.branch_repo_ref == repo_full do
      {:noreply,
       socket
       |> assign(:branch_async, AsyncResult.ok(branches))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:branches, repo_full}, {:ok, {:error, reason}}, socket) do
    if socket.assigns.branch_repo_ref == repo_full do
      {:noreply,
       socket
       |> assign(:branch_async, AsyncResult.failed(socket.assigns.branch_async, reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:branches, repo_full}, {:exit, reason}, socket) do
    if socket.assigns.branch_repo_ref == repo_full do
      {:noreply,
       socket
       |> assign(:branch_async, AsyncResult.failed(socket.assigns.branch_async, {:exit, reason}))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:branches, _repo_full}, _, socket) do
    {:noreply,
     assign(socket, :branch_async, AsyncResult.failed(socket.assigns.branch_async, :unknown))}
  end

  defp save_service(socket, :new_service, params) do
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
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create service: #{inspect(reason)}")}
    end
  end

  defp save_service(socket, :edit_service, params) do
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
         |> push_patch(to: socket.assigns.return_to)}

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

  defp maybe_start_branch_async(socket, changeset) do
    repo_full = repo_full_name_from_changeset(changeset)
    branch_async = socket.assigns[:branch_async] || AsyncResult.ok([])

    cond do
      is_nil(repo_full) ->
        socket
        |> assign(:branch_repo_ref, nil)
        |> assign(:branch_async, branch_async || AsyncResult.ok([]))

      repo_full == socket.assigns[:branch_repo_ref] and not is_nil(branch_async) ->
        socket

      true ->
        socket
        |> assign(:branch_repo_ref, repo_full)
        |> assign(:branch_async, AsyncResult.loading())
        |> maybe_start_branch_task(repo_full)
    end
  end

  defp maybe_start_branch_task(socket, repo_full) do
    {owner, repo} = parse_full_name(repo_full)
    provider = socket.assigns.provider

    if is_nil(owner) or is_nil(repo) do
      assign(
        socket,
        :branch_async,
        AsyncResult.failed(socket.assigns.branch_async, :invalid_repo)
      )
    else
      start_async(socket, {:branches, repo_full}, fn ->
        ProviderAdapters.list_branches(provider, owner, repo)
      end)
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

  defp branch_options(branches) do
    Enum.map(branches, fn branch ->
      label = branch_label(branch)
      {label, branch[:name]}
    end)
  end

  defp branch_label(branch) do
    name = branch[:name] || ""
    sha = branch[:commit_sha] && String.slice(branch[:commit_sha], 0, 7)

    cond do
      branch[:protected] && sha -> "#{name} (protected, #{sha})"
      branch[:protected] -> "#{name} (protected)"
      sha -> "#{name} (#{sha})"
      true -> name
    end
  end

  defp format_branch_error(:invalid_repo), do: "Select a repository first"
  defp format_branch_error(:unauthorized), do: "Unauthorized"
  defp format_branch_error(:forbidden), do: "Forbidden"
  defp format_branch_error(:not_found), do: "Repository not found"
  defp format_branch_error(:unsupported_auth_type), do: "Unsupported auth type"
  defp format_branch_error(:missing_token), do: "Missing token"
  defp format_branch_error({:unexpected_status, status}), do: "Unexpected response (#{status})"
  defp format_branch_error(reason), do: inspect(reason)

  defp repo_full_name_from_changeset(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.get_field(changeset, :repo_full_name)
  end

  defp branch_select_value(form) do
    case form[:default_ref] do
      %Phoenix.HTML.FormField{value: value} -> value
      _ -> nil
    end
  end

  defp normalize_branch(nil), do: nil

  defp normalize_branch(branch) when is_binary(branch) do
    branch = String.trim(branch)
    if branch == "", do: nil, else: branch
  end

  defp normalize_branch(_), do: nil

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
end
