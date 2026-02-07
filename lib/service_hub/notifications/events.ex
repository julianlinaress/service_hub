defmodule ServiceHub.Notifications.Events do
  @moduledoc """
  Internal event emitter used by notification checks.

  Persists emitted events for auditability and troubleshooting.
  """

  require Logger
  import Ecto.Query

  alias ServiceHub.Notifications.Event
  alias ServiceHub.Repo

  @spec emit(String.t(), map(), keyword()) :: :ok
  def emit(name, payload, opts \\ [])
      when is_binary(name) and is_map(payload) and is_list(opts) do
    tags = normalize_tags(Keyword.get(opts, :tags, %{}))
    actor = Keyword.get(opts, :actor)
    event_id = Keyword.get(opts, :id, Ecto.UUID.generate())
    source = Map.get(tags, "source")

    attrs = %{
      id: event_id,
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
        :telemetry.execute(
          [:service_hub, :notifications, :event, :persisted],
          %{count: 1},
          %{event_name: name, source: source}
        )

        :ok

      {:error, reason} ->
        :telemetry.execute(
          [:service_hub, :notifications, :event, :persist_failed],
          %{count: 1},
          %{event_name: name, source: source, reason: reason}
        )

        Logger.error("Failed to persist notification event: #{inspect(reason)}")
        :ok
    end
  end

  @spec prune_old_events(pos_integer()) :: non_neg_integer()
  def prune_old_events(retention_days \\ 90)
      when is_integer(retention_days) and retention_days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 24 * 60 * 60, :second)

    {count, _} =
      Event
      |> where([event], event.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  defp normalize_tags(tags) when is_map(tags), do: tags

  defp normalize_tags(tags) when is_list(tags) do
    if Keyword.keyword?(tags) do
      tags
      |> Enum.into(%{})
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_tags(_), do: %{}
end
