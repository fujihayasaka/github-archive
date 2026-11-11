# typed: true
# frozen_string_literal: true

module ChecksRollupHelper

  # Calculate the status to represent a group of check runs based on the lowest hierarchical check run status
  # From highest to lowest priority status. For more information about the types of states see packages/checks/apps/models/check_run.rb
  # -- requested
  # -- pending
  # -- waiting
  # -- queued
  # -- in_progress
  # -- completed
  #
  # Returns a string.
  def calculate_rollup_status(check_runs)
    lowest_run = check_runs.
      min_by { |run| get_check_run_logical_status(run) }

    lowest_run&.status || "requested"
  end

  # Calculates a single conclusion for a group of check runs
  # From highest to lowest conclusion, for more information about the types of conclusions see packages/checks/apps/models/check_run.rb
  # -- action_required
  # -- stale
  # -- timed_out
  # -- failure
  # -- cancelled
  # -- success
  # -- neutral
  # -- skipped
  #
  # Returns a string or nil.
  def calculate_rollup_conclusion(check_runs)
    concluded_check_runs = check_runs.select { |check_run| check_run.status == "completed" }
    lowest_run = concluded_check_runs.
      min_by { |run| CONCLUSIONS_HIERARCHY.index(run.conclusion) }

    lowest_run&.conclusion
  end

  # Statuses added after initial implementation can be higher in value, but lower in terms of chronological order
  private def get_check_run_logical_status(check_run)
    # Jobs can be pending before they are set to waiting
    # waiting comes right after "requested", so honor that while calculating rollup
    case check_run.status
    when "waiting"
      -0.5
    when "pending"
      -0.75
    else
      CheckSuite.statuses[check_run.status]
    end
  end

  CONCLUSIONS_HIERARCHY = %w(action_required stale timed_out failure cancelled success neutral skipped)
end
