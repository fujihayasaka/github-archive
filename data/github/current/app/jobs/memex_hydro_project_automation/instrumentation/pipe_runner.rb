# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation::Instrumentation::PipeRunner
  include MemexHydroProjectAutomation::Instrumentation::Shared

  METRIC_TRIGGERED = "#{METRIC_PREFIX}.workflow_run_triggered"
  # Time to run a workflow
  METRIC_DURATION = "#{METRIC_PREFIX}.workflow_run_duration.ms"
  # Time from hydro event enqueued to workflow completion
  METRIC_END_TO_END_DURATION = "#{METRIC_PREFIX}.workflow_run_end_to_end_duration.ms"
  METRIC_INVALID_WORKFLOW_MESSAGE = "#{METRIC_PREFIX}.workflow_run_invalid_workflow"

  # Default tags to include in all Workflow metrics.
  #
  # Returns Array<String>
  def stats_tags_default
    [
      "trigger_type:#{@trigger_type}",
      "runner:piped",
      "manual_run:#{@manual_run}",
    ] + @tags
  end

  # Builds a generic workflow log payload
  def log_payload(**extra)
    {
      trigger_type: @trigger_type,
      manual_run: @manual_run,
      actor_id: @actor&.id,
      project_id: @workflow&.memex_project_id,
      workflow_id: @workflow&.id,
      input: @input&.map { |item| [item&.class&.name, item&.id] },
      actions: @workflow&.actions&.map { |action| [action&.id, action&.action_type] },
    }.merge(extra)
  end

  def log_end_to_end_duration(start_time, **extra)
    context = log_payload.merge(extra)
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution(METRIC_END_TO_END_DURATION, elapsed, tags: stats_tags_default)
    log("Completed WORKFLOW run end to end in #{elapsed}ms: #{context.inspect}")
  end

  # Log workflow containing invalid actions
  def log_invalid_workflow(**extra)
    context = log_payload.merge(extra)
    GitHub.dogstats.increment(METRIC_INVALID_WORKFLOW_MESSAGE, tags: stats_tags_default)
    log("Found invalid workflow: #{@workflow}. Aborting workflow execution: #{context.inspect}")
  end
end
