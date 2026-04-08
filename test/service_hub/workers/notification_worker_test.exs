defmodule ServiceHub.Workers.NotificationWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  alias ServiceHub.Workers.NotificationWorker

  describe "perform/1" do
    test "calls EventHandler.handle_event with the event data" do
      # The worker should succeed even if no rules match (EventHandler returns :ok)
      event = %{
        "name" => "health.alert",
        "payload" => %{
          "service_id" => 1,
          "deployment_id" => 1,
          "check_type" => "health",
          "message" => "Health check failed",
          "metadata" => %{"host" => "test.example.com", "env" => "test"}
        },
        "tags" => %{"source" => "automatic"}
      }

      assert :ok = perform_job(NotificationWorker, %{event: event})
    end
  end

  describe "backoff/1" do
    test "returns exponential backoff" do
      assert NotificationWorker.backoff(%Oban.Job{attempt: 1}) == 30
      assert NotificationWorker.backoff(%Oban.Job{attempt: 2}) == 90
    end
  end
end
