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
          {Phoenix.HTML.raw(icon_path(@type))}
        </svg>
      </div>
      <span :if={@with_label} class={["font-medium", label_size(@size)]}>
        {label(@type)}
      </span>
    </div>
    """
  end

  defp size_class("sm"), do: "w-8 h-8"
  defp size_class("md"), do: "w-10 h-10"
  defp size_class("lg"), do: "w-12 h-12"
  defp size_class("xl"), do: "w-16 h-16"

  defp icon_size("sm"), do: "size-5"
  defp icon_size("md"), do: "size-7"
  defp icon_size("lg"), do: "size-8"
  defp icon_size("xl"), do: "size-10"

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
    <svg version="1.1" id="main_outline" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" style="enable-background:new 0 0 640 640;" xml:space="preserve" viewBox="5.67 143.05 628.65 387.55"> <g> 	<path id="teabag" style="fill:#FFFFFF" d="M395.9,484.2l-126.9-61c-12.5-6-17.9-21.2-11.8-33.8l61-126.9c6-12.5,21.2-17.9,33.8-11.8   c17.2,8.3,27.1,13,27.1,13l-0.1-109.2l16.7-0.1l0.1,117.1c0,0,57.4,24.2,83.1,40.1c3.7,2.3,10.2,6.8,12.9,14.4   c2.1,6.1,2,13.1-1,19.3l-61,126.9C423.6,484.9,408.4,490.3,395.9,484.2z"></path> 	<g> 		<g> 			<path style="fill:#609926" d="M622.7,149.8c-4.1-4.1-9.6-4-9.6-4s-117.2,6.6-177.9,8c-13.3,0.3-26.5,0.6-39.6,0.7c0,39.1,0,78.2,0,117.2     c-5.5-2.6-11.1-5.3-16.6-7.9c0-36.4-0.1-109.2-0.1-109.2c-29,0.4-89.2-2.2-89.2-2.2s-141.4-7.1-156.8-8.5     c-9.8-0.6-22.5-2.1-39,1.5c-8.7,1.8-33.5,7.4-53.8,26.9C-4.9,212.4,6.6,276.2,8,285.8c1.7,11.7,6.9,44.2,31.7,72.5     c45.8,56.1,144.4,54.8,144.4,54.8s12.1,28.9,30.6,55.5c25,33.1,50.7,58.9,75.7,62c63,0,188.9-0.1,188.9-0.1s12,0.1,28.3-10.3     c14-8.5,26.5-23.4,26.5-23.4s12.9-13.8,30.9-45.3c5.5-9.7,10.1-19.1,14.1-28c0,0,55.2-117.1,55.2-231.1     C633.2,157.9,624.7,151.8,622.7,149.8z M125.6,353.9c-25.9-8.5-36.9-18.7-36.9-18.7S69.6,321.8,60,295.4     c-16.5-44.2-1.4-71.2-1.4-71.2s8.4-22.5,38.5-30c13.8-3.7,31-3.1,31-3.1s7.1,59.4,15.7,94.2c7.2,29.2,24.8,77.7,24.8,77.7     S142.5,359.9,125.6,353.9z M425.9,461.5c0,0-6.1,14.5-19.6,15.4c-5.8,0.4-10.3-1.2-10.3-1.2s-0.3-0.1-5.3-2.1l-112.9-55     c0,0-10.9-5.7-12.8-15.6c-2.2-8.1,2.7-18.1,2.7-18.1L322,273c0,0,4.8-9.7,12.2-13c0.6-0.3,2.3-1,4.5-1.5c8.1-2.1,18,2.8,18,2.8     l110.7,53.7c0,0,12.6,5.7,15.3,16.2c1.9,7.4-0.5,14-1.8,17.2C474.6,363.8,425.9,461.5,425.9,461.5z"></path> 			<path style="fill:#609926" d="M326.8,380.1c-8.2,0.1-15.4,5.8-17.3,13.8c-1.9,8,2,16.3,9.1,20c7.7,4,17.5,1.8,22.7-5.4     c5.1-7.1,4.3-16.9-1.8-23.1l24-49.1c1.5,0.1,3.7,0.2,6.2-0.5c4.1-0.9,7.1-3.6,7.1-3.6c4.2,1.8,8.6,3.8,13.2,6.1     c4.8,2.4,9.3,4.9,13.4,7.3c0.9,0.5,1.8,1.1,2.8,1.9c1.6,1.3,3.4,3.1,4.7,5.5c1.9,5.5-1.9,14.9-1.9,14.9     c-2.3,7.6-18.4,40.6-18.4,40.6c-8.1-0.2-15.3,5-17.7,12.5c-2.6,8.1,1.1,17.3,8.9,21.3c7.8,4,17.4,1.7,22.5-5.3     c5-6.8,4.6-16.3-1.1-22.6c1.9-3.7,3.7-7.4,5.6-11.3c5-10.4,13.5-30.4,13.5-30.4c0.9-1.7,5.7-10.3,2.7-21.3     c-2.5-11.4-12.6-16.7-12.6-16.7c-12.2-7.9-29.2-15.2-29.2-15.2s0-4.1-1.1-7.1c-1.1-3.1-2.8-5.1-3.9-6.3c4.7-9.7,9.4-19.3,14.1-29     c-4.1-2-8.1-4-12.2-6.1c-4.8,9.8-9.7,19.7-14.5,29.5c-6.7-0.1-12.9,3.5-16.1,9.4c-3.4,6.3-2.7,14.1,1.9,19.8     C343.2,346.5,335,363.3,326.8,380.1z"></path> 		</g> 	</g> </g> </svg>
    """
  end

  defp icon_path(_type) do
    # Default cloud icon for unknown types
    """
    <path d="M17.5 14.25c2.347 0 4.5-1.653 4.5-4.25 0-2.597-2.153-4.25-4.5-4.25-.303 0-.598.028-.882.082C15.843 3.929 14.076 2.5 12 2.5c-2.796 0-5.07 2.274-5.07 5.07 0 .233.016.463.047.688C4.383 8.832 2.5 10.965 2.5 13.5c0 2.9 2.35 5.25 5.25 5.25h9.75z"/>
    """
  end
end
