defmodule ServiceHubWeb.Components.Status.HealthBadge do
  @moduledoc """
  Health status badge component with color coding.
  """
  use Phoenix.Component

  @doc """
  Renders a health status badge.

  ## Examples

      <.health_badge status="ok" />
      <.health_badge status="warning" size="sm" />
      <.health_badge status="down" with_icon={false} />
  """
  attr :status, :string, required: true
  attr :size, :string, default: "md", values: ["xs", "sm", "md", "lg"]
  attr :with_icon, :boolean, default: true
  attr :class, :string, default: ""

  def health_badge(assigns) do
    ~H"""
    <span class={[
      "badge gap-1",
      size_class(@size),
      color_class(@status),
      @class
    ]}>
      <svg
        :if={@with_icon}
        class={icon_size(@size)}
        fill="currentColor"
        viewBox="0 0 8 8"
        aria-hidden="true"
      >
        <circle cx="4" cy="4" r="3" />
      </svg>
      <span><%= label(@status) %></span>
    </span>
    """
  end

  defp size_class("xs"), do: "badge-xs"
  defp size_class("sm"), do: "badge-sm"
  defp size_class("md"), do: "badge-md"
  defp size_class("lg"), do: "badge-lg"

  defp icon_size("xs"), do: "w-1.5 h-1.5"
  defp icon_size("sm"), do: "w-2 h-2"
  defp icon_size("md"), do: "w-2.5 h-2.5"
  defp icon_size("lg"), do: "w-3 h-3"

  defp color_class("ok"), do: "badge-ghost"
  defp color_class("warning"), do: "badge-ghost"
  defp color_class("down"), do: "badge-ghost"
  defp color_class("unknown"), do: "badge-ghost"
  defp color_class(_), do: "badge-ghost"

  defp label("ok"), do: "Healthy"
  defp label("warning"), do: "Warning"
  defp label("down"), do: "Down"
  defp label("unknown"), do: "Unknown"
  defp label(status), do: status
end
