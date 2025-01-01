# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSecurityProductsDependencyTest < GitHub::TestCase
  fixtures do
    @business = GitHub.enterprise? ? create(:global_business) : create(:business)
    @org = create(:organization, business: @business)
    @sibling_org = create(:organization, business: @business)
    @non_business_org = create(:organization, skip_enterprise_managed_organization: true)
  end

  context "#security_configurations_applying_or_blocked?" do
    test "returns true if BlockedSettings are active for the org" do
      # Block a setting for the org:
      setting = :auto_codeql_enable_all

      # Track a job and ensure we return true:
      job_status = SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
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

    test "calls sibling_orgs_applying_security_configurations?" do
      @org.expects(:sibling_orgs_applying_security_configurations?).once.returns(false)
      @org.security_configurations_applying_or_blocked?
    end
  end

  context "#sibling_orgs_applying_security_configurations?" do
    test "returns false if the org is not owned by a business" do
      assert_nil @non_business_org.business
      SecurityProductsEnablement::JobProgressTracker.expects(:business_jobs_running?).never
      refute_predicate @non_business_org, :sibling_orgs_applying_security_configurations?
    end

    test "returns false if the org is owned by a business but no other jobs are in progress" do
      assert @org.business.present?
      refute_predicate @org, :sibling_orgs_applying_security_configurations?
    end

    test "returns true if the org is owned by a business and other jobs are in progress" do
      # Ensure that the org and sibling org have the same owner:
      assert_equal @org.business.id, @sibling_org.business.id

      # Start jobs for a sibling org owned by the same Business:
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@sibling_org.id, @sibling_org.business.id)
      job_progress_tracker.start
      assert_predicate @org, :sibling_orgs_applying_security_configurations?

      job_progress_tracker.finish
      refute_predicate @org, :sibling_orgs_applying_security_configurations?
    end
  end
end
