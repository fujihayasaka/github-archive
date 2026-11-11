# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation::Instrumentation::PipedActions
  include MemexHydroProjectAutomation::Instrumentation::Shared

  METRIC_TRIGGERED = "#{METRIC_PREFIX}.action_triggered"
  METRIC_SKIPPED = "#{METRIC_PREFIX}.action_skipped"
  METRIC_DURATION = "#{METRIC_PREFIX}.action_duration.ms"

  REASON_ARCHIVED = "project item already archived"
  REASON_EXISTS = "item already exists in project"
  REASON_RECORD_INVALID = "record is invalid"
  REASON_CANNOT_BE_CLOSED = "item cannot be closed"
  REASON_DOES_NOT_HAVE_CONTENT = "item does not have content"
  REASON_IS_NOT_AN_ISSUE = "item is not an issue"
  REASON_NO_ACCESS = "actor does not have access to perform action"

  # Default tags to include in all Workflow metrics.
  #
  # Returns Array<String>
  def stats_tags_default
    [
      "trigger_type:#{@trigger_type}",
      "runner:piped",
      "action_type:#{@action.action_type}",
      "manual_run:#{@manual_run}",
    ] + @tags
  end

  # Log and stat a skip of an action
  #
  # params - Hash - any key => val params to include in the log message.
  #
  # Returns nothing
  def log_action_skipped(**params)
    GitHub.dogstats.increment(
      METRIC_SKIPPED,
      tags: stats_tags_default + ["reason:#{params[:reason]}"]
    )
    log("Skipped action with the following context: #{params.inspect}")
  end

  # Builds a generic action log payload
  def log_payload(project_item: nil, **extra)
    {
      content_type: project_item&.content_type,
      content_id: project_item&.content_id,
      trigger_type: @trigger_type,
      manual_run: @manual_run,
      actor_id: @actor&.id,
      project_id: @action&.workflow&.memex_project_id,
      action_id: @action&.id,
      action_type: @action&.action_type,
      project_item_id: project_item&.id,
    }.merge(extra)
  end
end
