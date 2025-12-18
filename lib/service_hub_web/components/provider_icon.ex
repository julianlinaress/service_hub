defmodule ServiceHubWeb.Components.ProviderIcon do
  @moduledoc """
  Provider-specific icon and branding component.
  Uses CSS variables for theming (--color-github, --color-gitea).
  """
  use Phoenix.Component

  @doc """
  Renders a provider icon with brand colors.

  ## Examples

      <.provider_icon type="github" />
      <.provider_icon type="gitea" size="lg" />
      <.provider_icon type="github" with_label />
  """
  attr :type, :string, required: true
  attr :size, :string, default: "md", values: ["sm", "md", "lg", "xl"]
  attr :with_label, :boolean, default: false
  attr :class, :string, default: ""

  def provider_icon(assigns) do
    ~H"""
    <div class={["inline-flex items-center gap-2", @class]}>
      <div class={[
        "flex items-center justify-center rounded-lg",
        size_class(@size),
        bg_class(@type)
      ]}>
        <svg class={icon_size(@size)} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <%= Phoenix.HTML.raw(icon_path(@type)) %>
        </svg>
      </div>
      <span :if={@with_label} class={["font-medium", label_size(@size)]}>
        <%= label(@type) %>
      </span>
    </div>
    """
  end

  defp size_class("sm"), do: "w-8 h-8"
  defp size_class("md"), do: "w-10 h-10"
  defp size_class("lg"), do: "w-12 h-12"
  defp size_class("xl"), do: "w-16 h-16"

  defp icon_size("sm"), do: "w-4 h-4"
  defp icon_size("md"), do: "w-5 h-5"
  defp icon_size("lg"), do: "w-6 h-6"
  defp icon_size("xl"), do: "w-8 h-8"

  defp label_size("sm"), do: "text-sm"
  defp label_size("md"), do: "text-base"
  defp label_size("lg"), do: "text-lg"
  defp label_size("xl"), do: "text-xl"

  defp bg_class("github"), do: "bg-[var(--color-github)] text-[var(--color-github-content)]"
  defp bg_class("gitea"), do: "bg-[var(--color-gitea)] text-[var(--color-gitea-content)]"
  defp bg_class(_), do: "bg-base-300 text-base-content"

  defp label("github"), do: "GitHub"
  defp label("gitea"), do: "Gitea"
  defp label(type), do: type

  # GitHub icon (official mark)
  defp icon_path("github") do
    """
    <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.865 8.17 6.839 9.49.5.092.682-.217.682-.482 0-.237-.008-.866-.013-1.7-2.782.603-3.369-1.34-3.369-1.34-.454-1.156-1.11-1.463-1.11-1.463-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.087 2.91.831.092-.646.35-1.086.636-1.336-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0112 6.836c.85.004 1.705.114 2.504.336 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C19.138 20.167 22 16.418 22 12c0-5.523-4.477-10-10-10z"/>
    """
  end

  # Gitea icon (tea leaf)
  defp icon_path("gitea") do
    """
    <path d="M12.296 4.135c-.473-.303-1.12-.303-1.593 0L4.036 8.613a2.035 2.035 0 00-.843 1.647v8.98c0 .686.343 1.327.912 1.708l6.667 4.468c.473.317 1.12.317 1.593 0l6.667-4.468a2.035 2.035 0 00.912-1.708v-8.98c0-.678-.338-1.312-.843-1.647l-6.805-4.478zm6.212 11.837l-3.152 2.06c-.178.116-.406.116-.584 0l-2.772-1.81-2.772 1.81c-.178.116-.406.116-.584 0l-3.152-2.06a.47.47 0 01-.204-.383V10.26c0-.152.074-.294.198-.38l3.158-2.172a.658.658 0 01.745 0l2.611 1.797 2.611-1.797a.658.658 0 01.745 0l3.158 2.172c.124.086.198.228.198.38v5.328a.47.47 0 01-.204.383z"/>
    """
  end

  defp icon_path(_type) do
    # Default cloud icon for unknown types
    """
    <path d="M17.5 14.25c2.347 0 4.5-1.653 4.5-4.25 0-2.597-2.153-4.25-4.5-4.25-.303 0-.598.028-.882.082C15.843 3.929 14.076 2.5 12 2.5c-2.796 0-5.07 2.274-5.07 5.07 0 .233.016.463.047.688C4.383 8.832 2.5 10.965 2.5 13.5c0 2.9 2.35 5.25 5.25 5.25h9.75z"/>
    """
  end
end
