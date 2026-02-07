defmodule ServiceHub.Notifications.Events do
  @moduledoc """
  Internal event emitter used by notification checks.

  Persists emitted events for auditability and troubleshooting.
  """

  require Logger

  alias ServiceHub.Notifications.Event
  alias ServiceHub.Repo

  @spec emit(String.t(), map(), keyword()) :: :ok
  def emit(name, payload, opts \\ [])
      when is_binary(name) and is_map(payload) and is_list(opts) do
    tags = Keyword.get(opts, :tags, %{})
    actor = Keyword.get(opts, :actor)
    source = Map.get(tags, "source")

    attrs = %{
      id: Ecto.UUID.generate(),
      name: name,
      payload: payload,
      tags: tags,
      actor: actor,
      source: source
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to persist notification event: #{inspect(reason)}")
        :ok
    end
  end
end
