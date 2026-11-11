# frozen_string_literal: true

class ReviewUpdateConfigRateLimit < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  def perform(update_job:)
    Dependabot::Exceptions.push(
      update_job.telemetry_attributes.merge(update_job.update_config.telemetry_attributes),
    )

    @update_job = update_job

    Statesman::Machine.retry_conflicts do
      return unless update_config.in_state?(:rate_limited)
      return unless rate_limit_did_not_bind?

      update_config.transition_to!(:active)
    end
  end

  private

  attr_reader :update_job

  def update_config
    @update_config ||= update_job.update_config
  end

  def rate_limit_did_not_bind?
    return false if update_job.dependencies&.any?
    return false if update_job.security_updates_only?
    return false unless update_job.in_state?(:processed)
    return false if update_job.pending_pull_requests.any?

    pr_count = update_job.pull_requests.count

    # If no PRs were created it may have been due to a bug. There's no
    # harm in keeping the update config rate-limited for now, so do that.
    return false if pr_count.zero?

    limit = update_job.update_config.open_pull_requests_limit
    return true unless limit

    pr_count < limit
  end
end
