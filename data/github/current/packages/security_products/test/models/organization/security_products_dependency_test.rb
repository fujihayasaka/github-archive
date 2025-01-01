# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSecurityProductsDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context "#security_configurations_applying_or_blocked?" do
    test "returns true if BlockedSettings are active for the org" do
      # Block a setting for the org:
      setting = :auto_codeql_enable_all

      # Track a job and ensure we return true:
      job_status = JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
      assert_predicate @org, :security_configurations_applying_or_blocked?

      # Mark the job as finished and ensure we return false:
      job_status.success!
      refute_predicate @org, :security_configurations_applying_or_blocked?
    end

    test "returns true if SecurityProductsEnablement::JobProgressTracker is in progress for the org" do
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)

      # Start job progress and ensure we return true:
      job_progress_tracker.start
      assert_predicate @org, :security_configurations_applying_or_blocked?

      # Finish job progress and ensure we return false:
      job_progress_tracker.finish
      refute_predicate @org, :security_configurations_applying_or_blocked?
    end

    test "returns false by default" do
      refute_predicate @org, :security_configurations_applying_or_blocked?
    end
  end
end
