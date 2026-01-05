defmodule ServiceHub.Automations.Behaviour do
  @moduledoc """
  Behaviour for defining automation tasks.

  An automation defines what targets to run on and how to execute the automation.
  The scheduler will periodically query for due targets and execute them using
  the Runner module.
  """

  @doc """
  Returns the unique identifier for this automation (e.g., "deployment_health").
  """
  @callback id() :: String.t()

  @doc """
  Returns an Ecto query that selects eligible target IDs.
  This query should include all scoping and filtering logic.

  Example:
      from d in Deployment,
        where: d.automatic_checks_enabled == true,
        where: is_nil(d.deleted_at),
        select: d.id
  """
  @callback targets_query() :: Ecto.Query.t()

  @doc """
  Executes the automation for a specific target.
  Receives the full AutomationTarget struct with all metadata.

  Should return:
  - {:ok, summary} - automation succeeded
  - {:warning, summary} - automation completed with warnings
  - {:error, reason} - automation failed
  """
  @callback run(target :: ServiceHub.Automations.AutomationTarget.t()) ::
              {:ok, String.t()} | {:warning, String.t()} | {:error, term()}

  @doc """
  Optional: Returns the timeout in seconds for this automation.
  Defaults to 30 seconds.
  """
  @callback timeout_seconds() :: pos_integer()

  @doc """
  Optional: Returns the maximum consecutive failures before auto-pause.
  Defaults to 5.
  """
  @callback max_failures() :: pos_integer()

  @doc """
  Optional: Returns the backoff curve as {base_minutes, multiplier, cap_minutes}.
  Defaults to {2, 2, 120} which gives: 2m, 4m, 8m, 16m, 32m, 64m, 120m (cap).
  """
  @callback backoff_curve() :: {pos_integer(), pos_integer(), pos_integer()}

  @doc """
  Optional: Returns the concurrency limit for this automation type.
  Defaults to the global concurrency limit.
  """
  @callback concurrency_limit() :: pos_integer() | nil

  @optional_callbacks timeout_seconds: 0,
                      max_failures: 0,
                      backoff_curve: 0,
                      concurrency_limit: 0

  @doc """
  Returns the timeout in seconds, using the callback if defined, otherwise the default.
  """
  def timeout_seconds(module) do
    if function_exported?(module, :timeout_seconds, 0) do
      module.timeout_seconds()
    else
      30
    end
  end

  @doc """
  Returns the max failures, using the callback if defined, otherwise the default.
  """
  def max_failures(module) do
    if function_exported?(module, :max_failures, 0) do
      module.max_failures()
    else
      5
    end
  end

  @doc """
  Returns the backoff curve, using the callback if defined, otherwise the default.
  """
  def backoff_curve(module) do
    if function_exported?(module, :backoff_curve, 0) do
      module.backoff_curve()
    else
      {2, 2, 120}
    end
  end

  @doc """
  Returns the concurrency limit, using the callback if defined, otherwise nil (use global).
  """
  def concurrency_limit(module) do
    if function_exported?(module, :concurrency_limit, 0) do
      module.concurrency_limit()
    else
      nil
    end
  end
end
