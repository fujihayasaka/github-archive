# frozen_string_literal: true

# This module handles broken repository detection and metric emission
module BrokenRepoHandler
  extend ActiveSupport::Concern

  include BrokenRepoDetection
  include BrokenRepoMetrics

  private

  def should_handle_broken_config?(update_config)
    broken?(update_config)
  end

  def handle_broken_config(update_config, enqueue_scheduled_update_id)
    job = most_recent_job(update_config)
    errors = job&.unique_errors&.map(&:error_type)

    log_broken_repo(update_config, errors)
    emit_compute_reduction_metric(update_config, errors)

    return true if broken_state(update_config) == :broken

    if errors.size.positive?
      mark_config_broken(update_config, enqueue_scheduled_update_id)
      return true
    end
    # If the most recent job has no update_job_errors, then it may be in a state where it needs
    # to be disabled. Allow the update to continue, which will sync and offboard if needed.

    false
  end
end
