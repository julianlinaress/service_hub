defmodule ServiceHub.Automations.RunnerTest do
  use ServiceHub.DataCase

  alias ServiceHub.Automations.{AutomationTarget, AutomationRun, Runner}

  # Test automation module that returns success
  defmodule SuccessAutomation do
    @behaviour ServiceHub.Automations.Behaviour

    def id, do: "test_success"
    def targets_query, do: from(fragment("SELECT 1 as id"))
    def run(_target), do: {:ok, "Test passed"}
    def timeout_seconds, do: 5
    def max_failures, do: 3
    def backoff_curve, do: {2, 2, 120}
  end

  # Test automation module that returns error
  defmodule FailureAutomation do
    @behaviour ServiceHub.Automations.Behaviour

    def id, do: "test_failure"
    def targets_query, do: from(fragment("SELECT 1 as id"))
    def run(_target), do: {:error, :test_error}
    def timeout_seconds, do: 5
    def max_failures, do: 3
    def backoff_curve, do: {2, 2, 120}
  end

  # Test automation module that times out
  defmodule TimeoutAutomation do
    @behaviour ServiceHub.Automations.Behaviour

    def id, do: "test_timeout"
    def targets_query, do: from(fragment("SELECT 1 as id"))

    def run(_target) do
      Process.sleep(10_000)
      {:ok, "This should timeout"}
    end

    def timeout_seconds, do: 1
    def max_failures, do: 3
    def backoff_curve, do: {2, 2, 120}
  end

  describe "execute/2" do
    setup do
      # Create a test automation target
      {:ok, target} =
        Repo.insert(
          AutomationTarget.changeset(%AutomationTarget{}, %{
            automation_id: "test_automation",
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

    test "executes successful automation and updates state", %{target: target} do
      result = Runner.execute(SuccessAutomation, target)

      assert {:ok, "Test passed"} = result

      # Check that target state was updated
      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.running_at == nil
      assert updated.last_status == "ok"
      assert updated.last_error == nil
      assert updated.consecutive_failures == 0
      assert updated.last_finished_at != nil

      # Check that a run record was created
      run = Repo.one(from r in AutomationRun, where: r.target_id == ^target.target_id)
      assert run.status == "ok"
      assert run.automation_id == target.automation_id
      assert run.duration_ms != nil
    end

    test "handles automation failure and applies backoff", %{target: target} do
      result = Runner.execute(FailureAutomation, target)

      assert {:error, :test_error} = result

      # Check that target state was updated
      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.running_at == nil
      assert updated.last_status == "error"
      assert updated.last_error != nil
      assert updated.consecutive_failures == 1
      # next_run_at should be in the future (backoff applied)
      assert DateTime.compare(updated.next_run_at, DateTime.utc_now(:microsecond)) == :gt

      # Check that a run record was created
      run = Repo.one(from r in AutomationRun, where: r.target_id == ^target.target_id)
      assert run.status == "error"
    end

    test "handles timeout and marks as timeout", %{target: target} do
      result = Runner.execute(TimeoutAutomation, target)

      assert {:error, :timeout} = result

      # Check that target state was updated
      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.last_status == "timeout"
      assert updated.consecutive_failures == 1
    end

    test "auto-pauses after max failures", %{target: target} do
      # Set up target with 2 consecutive failures (max is 3)
      {:ok, target} =
        target
        |> AutomationTarget.changeset(%{consecutive_failures: 2})
        |> Repo.update()

      # Execute failing automation (this will be the 3rd failure)
      Runner.execute(FailureAutomation, target)

      # Check that target was paused
      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.consecutive_failures == 3
      assert updated.paused_at != nil
    end

    test "resets consecutive_failures on success after failures", %{target: target} do
      # Set up target with failures
      {:ok, target} =
        target
        |> AutomationTarget.changeset(%{consecutive_failures: 2})
        |> Repo.update()

      # Execute successful automation
      Runner.execute(SuccessAutomation, target)

      # Check that consecutive failures were reset
      updated = Repo.get!(AutomationTarget, target.id)
      assert updated.consecutive_failures == 0
      assert updated.paused_at == nil
    end
  end
end
