# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class TestSubclassJob < BaseJob
        def perform(repository_id:); end
      end

      class BaseJobTest < GitHub::TestCase
        include DogstatsTestHelpers
        include JobTestHelper
        include GitHub::LoggerHelper

        fixtures do
          @biz = create(:business)

          @org = create(:organization, business: @biz)
          @repo = create(:repository, owner: @org)
        end

        setup do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        end

        test "it retries on dirty exits, recoverable exceptions, and throttler exceptions" do
          assert_retry_conditions(job: TestSubclassJob, args: [{ repository_id: @repo.id }], using_kwargs: true)
        end

        test "it doesn't perform if repo is soft-deleted" do
          repo = create(:deleted_repository, owner: @org)
          TestSubclassJob.any_instance.expects(:perform).never
          TestSubclassJob.perform_now(repository_id: repo.id)
          assert_dogstats_increment 1, "security_overview_analytics.initialization.skipped", tags: ["reason:repository_deleted"]
        end

        test "it performs if owner is in scope" do
          TenantValidationHelper.expects(:is_owner_in_scope?).returns(true)
          TestSubclassJob.any_instance.expects(:perform).once
          TestSubclassJob.perform_now(repository_id: @repo.id)
          refute_dogstats_increment "security_overview_analytics.initialization.skipped"
        end

        test "it doesn't perform if owner is not in scope" do
          TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)
          TestSubclassJob.any_instance.expects(:perform).never
          TestSubclassJob.perform_now(repository_id: @repo.id)
          assert_dogstats_increment 1, "security_overview_analytics.initialization.skipped", tags: ["reason:tenant_not_in_scope"]
        end
      end
    end
  end
end
