defmodule ServiceHub.Repo.Migrations.BackfillAutomationTargetsForDeployments do
  use Ecto.Migration

  def up do
    # Backfill automation_targets for existing deployments with automatic checks enabled
    execute """
    INSERT INTO automation_targets (
      automation_id,
      target_type,
      target_id,
      enabled,
      interval_minutes,
      next_run_at,
      consecutive_failures,
      lock_version,
      inserted_at,
      updated_at
    )
    SELECT
      'deployment_health' as automation_id,
      'deployment' as target_type,
      id as target_id,
      true as enabled,
      check_interval_minutes as interval_minutes,
      now() as next_run_at,
      0 as consecutive_failures,
      1 as lock_version,
      now() as inserted_at,
      now() as updated_at
    FROM deployments
    WHERE automatic_checks_enabled = true
    ON CONFLICT (automation_id, target_type, target_id) DO NOTHING;
    """

    # Backfill version check automation targets for deployments with both automatic and version checks enabled
    execute """
    INSERT INTO automation_targets (
      automation_id,
      target_type,
      target_id,
      enabled,
      interval_minutes,
      next_run_at,
      consecutive_failures,
      lock_version,
      inserted_at,
      updated_at
    )
    SELECT
      'deployment_version' as automation_id,
      'deployment' as target_type,
      id as target_id,
      true as enabled,
      check_interval_minutes as interval_minutes,
      now() as next_run_at,
      0 as consecutive_failures,
      1 as lock_version,
      now() as inserted_at,
      now() as updated_at
    FROM deployments
    WHERE automatic_checks_enabled = true
      AND version_check_enabled = true
    ON CONFLICT (automation_id, target_type, target_id) DO NOTHING;
    """

    # Create a dummy automation target for the retention cleaner (runs hourly)
    execute """
    INSERT INTO automation_targets (
      automation_id,
      target_type,
      target_id,
      enabled,
      interval_minutes,
      next_run_at,
      consecutive_failures,
      lock_version,
      inserted_at,
      updated_at
    ) VALUES (
      'retention_cleaner',
      'system',
      1,
      true,
      60,
      now(),
      0,
      1,
      now(),
      now()
    )
    ON CONFLICT (automation_id, target_type, target_id) DO NOTHING;
    """
  end

  def down do
    # Remove all automation targets created by this migration
    execute "DELETE FROM automation_targets WHERE automation_id IN ('deployment_health', 'deployment_version', 'retention_cleaner');"
  end
end
