defmodule ServiceHub.Workers.RetentionCleanerWorkerTest do
  use ServiceHub.DataCase
  use Oban.Testing, repo: ServiceHub.Repo

  alias ServiceHub.Automations.AutomationRun
  alias ServiceHub.Workers.RetentionCleanerWorker

  describe "perform/1" do
    test "deletes old automation_runs beyond retention limits" do
      # Insert 55 runs for a target, all older than 45 days
      old_time = DateTime.add(DateTime.utc_now(), -45 * 24 * 3600, :second)

      for i <- 1..55 do
        run =
          Repo.insert!(
            AutomationRun.changeset(%AutomationRun{}, %{
              automation_id: "deployment_health",
              target_type: "deployment",
              target_id: 1,
              status: "ok",
              started_at: DateTime.add(old_time, i, :second),
              attempt: 1
            })
          )

        # Override inserted_at to be old enough for the retention query
        Repo.query!("UPDATE automation_runs SET inserted_at = $1 WHERE id = $2", [
          DateTime.add(old_time, i, :second),
          run.id
        ])
      end

      assert :ok = perform_job(RetentionCleanerWorker, %{})

      remaining =
        Repo.aggregate(
          from(r in AutomationRun,
            where: r.automation_id == "deployment_health" and r.target_id == 1
          ),
          :count
        )

      # Should keep 50 (the threshold), deleted 5
      assert remaining == 50
    end

    test "succeeds with no records to prune" do
      assert :ok = perform_job(RetentionCleanerWorker, %{})
    end
  end
end
