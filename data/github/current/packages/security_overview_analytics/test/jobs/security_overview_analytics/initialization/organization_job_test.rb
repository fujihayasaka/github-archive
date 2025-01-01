# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class OrganizationJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        @org = create(:business_plus_organization)
        @repos = create_list(:repository, 10, owner: @org)
      end

      setup do
        @initialization_for_org = SecurityOverviewAnalytics::Initialization.for(@org)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end
      end

      test "it enqueues an initialization job for each repo" do
        perform_enqueued_jobs(only: OrganizationJob) do
          OrganizationJob.perform_later(organization_id: @org.id)
        end

        assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::RepoMetadataJob)
        assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::FeatureEnablementJob)
        assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::CodeScanningAlertsJob)
        assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::SecretScanningAlertsJob)
        assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::DependabotAlertsJob)
      end

      context "when repos are soft-deleted" do
        test "it does not enqueue repo jobs for them" do
          ::Repository.where(id: @repos.map(&:id)).destroy_all
          create(:repository, :soft_deleted, owner: @org)

          perform_enqueued_jobs(only: OrganizationJob) do
            OrganizationJob.perform_later(organization_id: @org.id)
          end

          assert_no_enqueued_jobs(only: Repositories::RepoMetadataJob)
          assert_no_enqueued_jobs(only: Repositories::FeatureEnablementJob)
          assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob)
          assert_no_enqueued_jobs(only: Repositories::SecretScanningAlertsJob)
          assert_no_enqueued_jobs(only: Repositories::DependabotAlertsJob)
        end
      end

      context "when on GHES", enterprise_only: true do
        test "it does not enqueue initialization job for feature that is not available" do
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)
          refute SecurityOverviewAnalytics::Initialization.for(@org).all_initialized?

          perform_enqueued_jobs(only: OrganizationJob) do
            OrganizationJob.perform_later(organization_id: @org.id)
          end

          assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::RepoMetadataJob)
          assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::FeatureEnablementJob)
          assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::SecretScanningAlertsJob)
          assert_enqueued_jobs(@org.org_repositories.size, only: Repositories::DependabotAlertsJob)

          assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob)
          assert SecurityOverviewAnalytics::Initialization.for(@org).all_initialized?
        end
      end
    end
  end
end
