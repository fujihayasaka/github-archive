# typed: true
# frozen_string_literal: true

# This job is responsible for detecting when the keys set by SecurityProductsEnablement::JobProgressTracker
# are out of sync, and alerts us on it. The keys being out of sync can prevent customers from enabling
# security products for a long time. We have seen this happen when the remaining_jobs key has a non-zero value
# even when all jobs have completed, which can cause the in-progress key to not be deleted.
module SecurityProductsEnablement
  class ProgressTrackerKeysMonitorJob < ApplicationJob
    extend T::Sig

    queue_as :security_configurations
    schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

    sig { void }
    def perform
      redis = GitHub.job_coordination_redis

      org_ids = redis.smembers(SecurityProductsEnablement::JobProgressTracker::ORG_IDS_KEY).map(&:to_i)
      org_ids.each do |org_id|
        job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(org_id)
        next if job_progress_tracker.in_progress?

        remaining_jobs = job_progress_tracker.remaining_jobs
        next if remaining_jobs.nil?

        GitHub.logger.info(
          "Found stale security configurations job progress tracking keys",
          org_id:,
          remaining_jobs:,
          total_jobs: job_progress_tracker.total_jobs
        )
        GitHub.dogstats.increment("security_products_enablement.progress_tracker_monitor", tags: ["org_id:#{org_id}"])

        redis.srem(SecurityProductsEnablement::JobProgressTracker::ORG_IDS_KEY, org_id)
      end
    end
  end
end
