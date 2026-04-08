defmodule ServiceHub.Workers.HealthCheckWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  alias ServiceHub.Automations.{AutomationTarget, AutomationRun}
  alias ServiceHub.Workers.HealthCheckWorker

  describe "perform/1" do
    test "returns ok when target not found" do
      assert :ok = perform_job(HealthCheckWorker, %{target_id: 0})
    end

    test "updates target state on deployment not found" do
      target =
        Repo.insert!(
          AutomationTarget.changeset(%AutomationTarget{}, %{
            automation_id: "deployment_health",
            target_type: "deployment",
            target_id: 99999,
            enabled: true,
            interval_minutes: 30,
            running_at: DateTime.utc_now(:microsecond),
            consecutive_failures: 0
          })
        )

      assert :ok = perform_job(HealthCheckWorker, %{target_id: 99999})

      updated = Repo.get!(AutomationTarget, target.id)
      assert is_nil(updated.running_at)
      assert updated.last_status == "error"
      assert updated.consecutive_failures == 1

      run = Repo.one(from r in AutomationRun, where: r.target_id == 99999)
      assert run.status == "error"
      assert run.automation_id == "deployment_health"
    end
  end
end
