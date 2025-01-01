# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor
  include MemexHydroProjectAutomation::Instrumentation::Shared

  METRIC_PREFIX = "memex.set_field_processor"
  METRIC_TRIGGERED = "#{METRIC_PREFIX}.action_triggered"
  METRIC_SKIPPED = "#{METRIC_PREFIX}.action_skipped"
  REASON_COLUMN_VALUE_EXISTS = "column value exists"
  REASON_REVIEWS_NOT_FULLFILED = "not all required reviews are fullfilled"
  REASON_PULL_REQUEST_MERGED = "pull request already merged"

  def stats_tags_default
    [
      "trigger_type:#{@trigger_type}",
    ] + @tags
  end

  # Log and stat an execution of the `set_field` action type.
  #
  # params - Hash - any key => val params to include in the log message.
  #
  # Returns nothing
  def log_set_field(**params)
    GitHub.dogstats.increment(
      METRIC_TRIGGERED,
      tags: stats_tags_default + ["action_type:#{params[:action_type]}"]
    )
    log("Triggered action with the following context: #{params.inspect}")
  end

  # Log and stat a skip of the `set_field` action type.
  #
  # params - Hash - any key => val params to include in the log message.
  #
  # Returns nothing
  def log_action_skipped(**params)
    GitHub.dogstats.increment(
      METRIC_SKIPPED,
      tags: stats_tags_default + ["action_type:#{params[:action_type]}", "reason:#{params[:reason]}"]
    )
    log("Skipped action with the following context: #{params.inspect}")
  end

  # Build the payload
  def log_payload(project_item, action, target_column, **extra)
    {
      content_type: project_item.content_type,
      content_id: project_item.content_id,
      trigger_type: @trigger_type,
      actor_id: @actor.id,
      project_id: project_item.memex_project_id,
      action_id: action.id,
      action_type: action.action_type,
      project_item_id: project_item.id,
      column_id: target_column.id,
      fieldOptionId: action["arguments"]["fieldOptionId"]
    }.merge(extra)
  end
end
