defmodule ServiceHub.Notifications.NotifierClientTest do
  use ServiceHub.DataCase

  alias ServiceHub.Notifications.NotifierClient

  setup do
    previous_impl = Application.get_env(:service_hub, :notifier_client_impl)

    Application.put_env(
      :service_hub,
      :notifier_client_impl,
      ServiceHub.Notifications.NotifierClientStub
    )

    on_exit(fn ->
      if previous_impl do
        Application.put_env(:service_hub, :notifier_client_impl, previous_impl)
      else
        Application.delete_env(:service_hub, :notifier_client_impl)
      end

      Process.delete(:notifier_client_response)
      Process.delete(:notifier_client_assertion)
    end)

    :ok
  end

  test "delegates delivery to configured notifier client implementation" do
    Process.put(:notifier_client_assertion, fn request ->
      assert request["provider"] == "telegram"
      assert request["delivery_attempt_key"] == "attempt-1"
    end)

    request = %{
      "provider" => "telegram",
      "delivery_attempt_key" => "attempt-1",
      "payload" => %{"text" => "hello"}
    }

    assert {:ok, %{status: :delivered, provider_response_code: "200"}} =
             NotifierClient.deliver(request)
  end

  test "returns normalized error tuple from configured client" do
    Process.put(:notifier_client_response, {
      :error,
      %{
        status: :failed,
        retryable: false,
        error_code: "invalid_payload",
        error_message: "invalid payload",
        provider_response_code: "422",
        provider_response: %{"error" => "bad payload"}
      }
    })

    assert {:error, error} = NotifierClient.deliver(%{"provider" => "slack"})
    assert error.retryable == false
    assert error.error_code == "invalid_payload"
    assert error.provider_response_code == "422"
  end
end
