# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class ProgressTrackerKeysMonitorJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include GitHub::LoggerHelper

    test "logs and instruments when the in-progress key does not exist, but the remaining_jobs key is present" do
      org_id = 20
      set_job_keys(org_id:, in_progress: false, remaining_jobs: 10, total_jobs: 15)

      # Set up other keys that should not trigger instrumentation
      set_job_keys(org_id: 39, in_progress: true, remaining_jobs: 1, total_jobs: 1)
      set_job_keys(org_id: 17, in_progress: true, remaining_jobs: 1, total_jobs: 1)

      assert_logged(org_id:, remaining_jobs: 10, total_jobs: 15) do
        SecurityProductsEnablement::ProgressTrackerKeysMonitorJob.perform_now
      end

      assert_dogstats_increment(1, "security_products_enablement.progress_tracker_monitor", tags: ["org_id:#{org_id}"])

      org_ids = redis.smembers(SecurityProductsEnablement::JobProgressTracker::ORG_IDS_KEY).map(&:to_i)
      refute org_ids.include?(org_id), "Expected the org_id to be removed from the set of org_ids"
    end

    test "does nothing when the in-progress key exists" do
      set_job_keys(org_id: 20, in_progress: true, remaining_jobs: 10, total_jobs: 15)

      refute_logged(org_id: 20, remaining_jobs: 10, total_jobs: 15) do
        SecurityProductsEnablement::ProgressTrackerKeysMonitorJob.perform_now
      end

      refute_dogstats_increment("security_products_enablement.progress_tracker_monitor")
    end

    test "does nothing when the in-progress key and remaining_jobs key do not exist" do
      set_job_keys(org_id: 20, in_progress: false, remaining_jobs: nil, total_jobs: nil)

      refute_logged(org_id: 20, remaining_jobs: nil, total_jobs: nil) do
        SecurityProductsEnablement::ProgressTrackerKeysMonitorJob.perform_now
      end

      refute_dogstats_increment("security_products_enablement.progress_tracker_monitor")
    end

    sig { params(org_id: Integer, in_progress: T::Boolean, remaining_jobs: T.nilable(Integer), total_jobs: T.nilable(Integer)).void }
    def set_job_keys(org_id:, in_progress: false, remaining_jobs: nil, total_jobs: nil)
      redis.sadd(SecurityProductsEnablement::JobProgressTracker::ORG_IDS_KEY, org_id)

      redis.set("security_configurations:#{org_id}:in_progress", 1) if in_progress
      redis.set("security_configurations:#{org_id}:remaining_jobs", remaining_jobs) if remaining_jobs.present?
      redis.set("security_configurations:#{org_id}:total_jobs", total_jobs) if total_jobs.present?
    end

    sig { returns(Redis) }
    def redis
      GitHub.job_coordination_redis
    end
  end
end unless GitHub.enterprise?
