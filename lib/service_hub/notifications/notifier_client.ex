defmodule ServiceHub.Notifications.NotifierClient do
  @moduledoc """
  Boundary for notification delivery requests to the external notifier service.
  """

  @type delivery_request :: map()

  @type success_response :: %{
          status: :delivered,
          provider_message_id: String.t() | nil,
          provider_response_code: String.t() | nil,
          provider_response: map()
        }

  @type error_response :: %{
          status: :failed,
          retryable: boolean(),
          error_code: String.t(),
          error_message: String.t(),
          provider_response_code: String.t() | nil,
          provider_response: map()
        }

  @callback deliver(delivery_request(), keyword()) ::
              {:ok, success_response()} | {:error, error_response()}

  @spec deliver(delivery_request(), keyword()) ::
          {:ok, success_response()} | {:error, error_response()}
  def deliver(request, opts \\ []) when is_map(request) and is_list(opts) do
    impl().deliver(request, opts)
  end

  defp impl do
    Application.get_env(
      :service_hub,
      :notifier_client_impl,
      ServiceHub.Notifications.NotifierClient.HTTP
    )
  end
end
