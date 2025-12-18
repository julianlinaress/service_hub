defmodule ServiceHubWeb.Components.Status.ValidationBadge do
  @moduledoc """
  Provider validation status badge component.
  """
  use Phoenix.Component

  @doc """
  Renders a validation status badge for providers.

  ## Examples

      <.validation_badge status="ok" />
      <.validation_badge status="error" size="sm" />
      <.validation_badge status="pending" />
  """
  attr :status, :string, required: true
  attr :size, :string, default: "md", values: ["xs", "sm", "md", "lg"]
  attr :with_icon, :boolean, default: true
  attr :class, :string, default: ""

  def validation_badge(assigns) do
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
  defp color_class("error"), do: "badge-ghost"
  defp color_class("pending"), do: "badge-ghost"
  defp color_class(_), do: "badge-ghost"

  defp label("ok"), do: "Validated"
  defp label("error"), do: "Invalid"
  defp label("pending"), do: "Pending"
  defp label(status), do: status
end
