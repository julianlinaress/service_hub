defmodule ServiceHubWeb.Components.Status.VersionDisplay do
  @moduledoc """
  Version display component with timestamp.
  """
  use Phoenix.Component

  @doc """
  Renders version information with optional timestamp.

  ## Examples

      <.version_display version="v1.2.3" />
      <.version_display version="v1.2.3" checked_at={~N[2024-01-01 10:00:00]} />
      <.version_display version={nil} />
  """
  attr :version, :string, default: nil
  attr :checked_at, :any, default: nil
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]
  attr :class, :string, default: ""

  def version_display(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @class]}>
      <code class={[
        "font-mono",
        text_size(@size),
        if(@version, do: "text-base-content", else: "text-base-content/40")
      ]}>
        <%= @version || "No version" %>
      </code>
      <div :if={@checked_at} class={["text-base-content/60", meta_size(@size)]}>
        Checked <%= relative_time(@checked_at) %>
      </div>
    </div>
    """
  end

  defp text_size("sm"), do: "text-xs"
  defp text_size("md"), do: "text-sm"
  defp text_size("lg"), do: "text-base"

  defp meta_size("sm"), do: "text-[10px]"
  defp meta_size("md"), do: "text-xs"
  defp meta_size("lg"), do: "text-sm"

  defp relative_time(nil), do: "never"

  defp relative_time(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} ->
        diff = DateTime.diff(DateTime.utc_now(), dt, :second)

        cond do
          diff < 60 -> "just now"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          diff < 604_800 -> "#{div(diff, 86400)}d ago"
          true -> Calendar.strftime(dt, "%b %d, %Y")
        end

      _ ->
        "unknown"
    end
  end
end
