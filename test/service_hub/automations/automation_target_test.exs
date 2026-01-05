defmodule ServiceHub.Automations.AutomationTargetTest do
  use ServiceHub.DataCase

  alias ServiceHub.Automations.AutomationTarget

  describe "automation_target changeset" do
    @valid_attrs %{
      automation_id: "deployment_health",
      target_type: "deployment",
      target_id: 123,
      enabled: true,
      interval_minutes: 30
    }

    test "changeset with valid attributes" do
      changeset = AutomationTarget.changeset(%AutomationTarget{}, @valid_attrs)
      assert changeset.valid?
    end

    test "changeset requires automation_id" do
      attrs = Map.delete(@valid_attrs, :automation_id)
      changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
      refute changeset.valid?
      assert %{automation_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset requires target_type" do
      attrs = Map.delete(@valid_attrs, :target_type)
      changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
      refute changeset.valid?
      assert %{target_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset requires target_id" do
      attrs = Map.delete(@valid_attrs, :target_id)
      changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
      refute changeset.valid?
      assert %{target_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset requires interval_minutes" do
      attrs = Map.delete(@valid_attrs, :interval_minutes)
      changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
      refute changeset.valid?
      assert %{interval_minutes: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset validates status inclusion" do
      attrs = Map.put(@valid_attrs, :last_status, "invalid_status")
      changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
      refute changeset.valid?
      assert %{last_status: ["is invalid"]} = errors_on(changeset)
    end

    test "changeset accepts valid statuses" do
      for status <- ["ok", "warning", "error", "timeout", "stale"] do
        attrs = Map.put(@valid_attrs, :last_status, status)
        changeset = AutomationTarget.changeset(%AutomationTarget{}, attrs)
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "insert enforces unique constraint on (automation_id, target_type, target_id)" do
      {:ok, _target} = Repo.insert(AutomationTarget.changeset(%AutomationTarget{}, @valid_attrs))

      # Try to insert duplicate
      assert {:error, changeset} =
               Repo.insert(AutomationTarget.changeset(%AutomationTarget{}, @valid_attrs))

      assert %{automation_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
