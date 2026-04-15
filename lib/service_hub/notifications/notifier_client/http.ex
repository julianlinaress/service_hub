defmodule ServiceHub.Notifications.NotifierClient.HTTP do
  @moduledoc false

  @behaviour ServiceHub.Notifications.NotifierClient

  @default_timeout 5_000

  @impl true
  def deliver(request, opts \\ []) do
    url = notifier_base_url() <> "/api/v1/deliveries"
    timeout = Keyword.get(opts, :timeout, notifier_timeout())

    case Req.post(url, json: request, receive_timeout: timeout) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        {:ok,
         %{
           status: :delivered,
           provider_message_id: body["provider_message_id"],
           provider_response_code: body["provider_response_code"] || to_string(status),
           provider_response: body["provider_response"] || body
         }}

      {:ok, %{status: status, body: body}} when status in [400, 422] ->
        {:error,
         %{
           status: :failed,
           retryable: false,
           error_code: body["error_code"] || "delivery_rejected",
           error_message: body["error_message"] || "Notifier rejected delivery request",
           provider_response_code: body["provider_response_code"] || to_string(status),
           provider_response: body["provider_response"] || body
         }}

      {:ok, %{status: status, body: body}} when status in [429, 500, 502, 503, 504] ->
        {:error,
         %{
           status: :failed,
           retryable: true,
           error_code: body["error_code"] || "notifier_unavailable",
           error_message: body["error_message"] || "Notifier service temporarily unavailable",
           provider_response_code: body["provider_response_code"] || to_string(status),
           provider_response: body["provider_response"] || body
         }}

      {:ok, %{status: status, body: body}} ->
        {:error,
         %{
           status: :failed,
           retryable: false,
           error_code: body["error_code"] || "notifier_unexpected_status",
           error_message: body["error_message"] || "Unexpected notifier response",
           provider_response_code: body["provider_response_code"] || to_string(status),
           provider_response: body["provider_response"] || body
         }}

      {:error, reason} ->
        {:error,
         %{
           status: :failed,
           retryable: true,
           error_code: "notifier_request_failed",
           error_message: inspect(reason),
           provider_response_code: nil,
           provider_response: %{}
         }}
    end
  end

  defp notifier_base_url do
    Application.get_env(:service_hub, :notifier_base_url, "http://localhost:8081")
    |> String.trim_trailing("/")
  end

  defp notifier_timeout do
    Application.get_env(:service_hub, :notifier_timeout_ms, @default_timeout)
  end
end
