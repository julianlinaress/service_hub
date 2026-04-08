defmodule ServiceHub.Workers.CheckHelpersTest do
  use ServiceHub.DataCase

  alias ServiceHub.Workers.CheckHelpers
  alias ServiceHub.Automations.{AutomationTarget, AutomationRun}

  @opts [max_failures: 3, backoff_curve: {2, 2, 120}]

  setup do
    {:ok, target} =
      Repo.insert(
        AutomationTarget.changeset(%AutomationTarget{}, %{
          automation_id: "deployment_health",
          target_type: "deployment",
          target_id: 999,
          enabled: true,
          interval_minutes: 30,
          next_run_at: DateTime.utc_now(:microsecond),
          running_at: DateTime.utc_now(:microsecond),
          consecutive_failures: 0
        })
      )

    %{target: target}
  end

  describe "update_target_state/5" do
    test "clears running_at and resets failures on success", %{target: target} do
      finished_at = DateTime.utc_now(:microsecond)
      CheckHelpers.update_target_state(target, "ok", nil, finished_at, @opts)

      updated = Repo.get!(AutomationTarget, target.id)
      assert is_nil(updated.running_at)
      assert updated.last_status == "ok"
      assert is_nil(updated.last_error)
      assert updated.consecutive_failures == 0
      assert is_nil(updated.paused_at)
      assert updated.last_finished_at != nil
    end

    test "increments failures and applies backoff on error", %{target: target} do
      finished_at = DateTime.utc_now(:microsecond)
      CheckHelpers.update_target_state(target, "error", "some error", finished_at, @opts)

      updated = Repo.get!(AutomationTarget, target.id)
      assert is_nil(updated.running_at)
      assert updated.last_status == "error"
      assert updated.last_error == "some error"
      assert updated.consecutive_failures == 1
      assert is_nil(updated.paused_at)
      assert DateTime.compare(updated.next_run_at, DateTime.utc_now(:microsecond)) == :gt
    end

    test "auto-pauses after max consecutive failures", %{target: target} do
      {:ok, target} =
        target
        |> AutomationTarget.changeset(%{consecutive_failures: 2})
        |> Repo.update()

      finished_at = DateTime.utc_now(:microsecond)
      CheckHelpers.update_target_state(target, "error", "fail", finished_at, @opts)

      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.consecutive_failures == 3
      assert updated.paused_at != nil
    end

    test "resets failures on success after prior failures", %{target: target} do
      {:ok, target} =
        target
        |> AutomationTarget.changeset(%{consecutive_failures: 2})
        |> Repo.update()

      finished_at = DateTime.utc_now(:microsecond)
      CheckHelpers.update_target_state(target, "ok", nil, finished_at, @opts)

      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.consecutive_failures == 0
      assert is_nil(updated.paused_at)
    end
  end

  describe "insert_run_record/7" do
    test "inserts an audit record", %{target: target} do
      started_at = DateTime.utc_now(:microsecond)
      finished_at = DateTime.add(started_at, 100, :millisecond)

      {:ok, run} =
        CheckHelpers.insert_run_record(
          target,
          "ok",
          "Health check passed",
          nil,
          started_at,
          finished_at,
          100
        )

      assert %AutomationRun{} = run
      assert run.automation_id == target.automation_id
      assert run.target_id == target.target_id
      assert run.status == "ok"
      assert run.summary == "Health check passed"
      assert run.duration_ms == 100
    end
  end

  describe "calculate_backoff/3" do
    test "applies exponential backoff" do
      curve = {2, 2, 120}

      # 1st failure: 2 * 2^0 = 2 minutes
      result = CheckHelpers.calculate_backoff(1, 5, curve)
      assert DateTime.compare(result, DateTime.utc_now(:microsecond)) == :gt

      # Backoff should never be less than interval
      result = CheckHelpers.calculate_backoff(1, 30, curve)
      diff = DateTime.diff(result, DateTime.utc_now(:microsecond), :second)
      # Should be at least 30 minutes (1800 seconds) minus a small tolerance
      assert diff >= 1790
    end
  end

  describe "normalize_health_result/1" do
    test "normalizes success" do
      assert {"ok", "Health check passed", nil} =
               CheckHelpers.normalize_health_result({:ok, %{}})
    end

    test "normalizes warning" do
      assert {"warning", msg, nil} =
               CheckHelpers.normalize_health_result({:warning, {:unexpected_status, 503}, %{}})

      assert msg =~ "warning"
    end

    test "normalizes error with deployment" do
      assert {"error", nil, error} =
               CheckHelpers.normalize_health_result({:error, :timeout, %{}})

      assert error =~ "timeout"
    end

    test "normalizes bare error" do
      assert {"error", nil, error} =
               CheckHelpers.normalize_health_result({:error, :not_found})

      assert error =~ "not_found"
    end
  end

  describe "normalize_version_result/1" do
    test "normalizes success" do
      assert {"ok", "Version check passed", nil} =
               CheckHelpers.normalize_version_result({:ok, %{}})
    end

    test "normalizes skipped" do
      assert {"ok", msg, nil} =
               CheckHelpers.normalize_version_result({:skipped, %{}})

      assert msg =~ "skipped"
    end
  end

  describe "get_target/2" do
    test "finds target by automation_id and target_id", %{target: target} do
      found = CheckHelpers.get_target("deployment_health", target.target_id)
      assert found.id == target.id
    end

    test "returns nil for non-existent target" do
      assert is_nil(CheckHelpers.get_target("deployment_health", 0))
    end
  end
end
