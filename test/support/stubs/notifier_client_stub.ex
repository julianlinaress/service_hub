defmodule ServiceHub.Notifications.NotifierClientStub do
  @behaviour ServiceHub.Notifications.NotifierClient

  @impl true
  def deliver(request, _opts) do
    response = Process.get(:notifier_client_response, default_success())

    if fun = Process.get(:notifier_client_assertion) do
      fun.(request)
    end

    response
  end

  defp default_success do
    {:ok,
     %{
       status: :delivered,
       provider_message_id: "stub-message-id",
       provider_response_code: "200",
       provider_response: %{"ok" => true}
     }}
  end
end
